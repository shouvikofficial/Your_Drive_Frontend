import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as dio;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../config/env.dart';
import '../services/vault_service.dart';

// ================= Upload Item =================
class UploadItem {
  final String id;
  final File file;
  double progress;
  String status;
  String? uploadId;
  dio.CancelToken? cancelToken;

  UploadItem({
    required this.file,
    this.progress = 0.0,
    this.status = 'waiting',
  }) : id = DateTime.now().microsecondsSinceEpoch.toString() +
            Random().nextInt(1000).toString();
}

// ================= Upload Manager (FINAL FIXED PARALLEL) =================
class UploadManager extends ChangeNotifier {
  static final UploadManager _instance = UploadManager._internal();
  factory UploadManager() => _instance;
  UploadManager._internal();

  List<UploadItem> uploadQueue = [];
  bool isUploading = false;

  String currentFolderName = "My Drive";
  String? currentFolderId;

  int filesProcessed = 0;
  int totalFilesToProcess = 0;

  final String chunkUploadUrl = "${Env.backendBaseUrl}/api/upload-chunk";
  final String cancelUploadUrl = "${Env.backendBaseUrl}/api/upload-cancel";

  // ================= Add Files =================
  Future<void> addFiles(List<File> files, String? folderId, String folderName) async {
    if (!isUploading) {
      currentFolderId = folderId;
      currentFolderName = folderName;
    }

    filesProcessed = 0;
    totalFilesToProcess = files.length;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 50));

    for (var file in files) {
      if (!uploadQueue.any((item) => item.file.path == file.path)) {
        uploadQueue.add(UploadItem(file: file));
      }

      filesProcessed++;

      if (filesProcessed % 5 == 0) {
        notifyListeners();
        await Future.delayed(Duration.zero);
      }
    }

    notifyListeners();
  }

  // ================= Auto Cache Clear =================
  Future<void> autoClearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();

      if (tempDir.existsSync()) {
        final files = tempDir.listSync();

        for (var file in files) {
          if (file is File) {
            if (file.path.endsWith('.enc') || file.path.contains('chunk')) {
              await file.delete();
            }
          }
        }
      }

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  // ================= Cancel Upload =================
  void cancelUpload(UploadItem item) async {
    if (item.status == 'uploading') {
      item.cancelToken?.cancel("User cancelled");
      item.status = 'cancelled';
      notifyListeners();

      if (item.uploadId != null) {
        try {
          await dio.Dio().post(cancelUploadUrl, data: {"upload_id": item.uploadId});
        } catch (_) {}
      }
    } else if (item.status == 'waiting') {
      removeFile(item);
    }
  }

  void removeFile(UploadItem item) {
    uploadQueue.remove(item);
    notifyListeners();
  }

  void clearCompleted() {
    uploadQueue.removeWhere((item) => ['done', 'exists', 'cancelled', 'error'].contains(item.status));
    autoClearCache();
    notifyListeners();
  }

  // ================= Start Batch Upload =================
  Future<void> startBatchUpload() async {
    if (isUploading) return;

    isUploading = true;
    notifyListeners();

    for (var item in uploadQueue) {
      if (['done', 'exists', 'cancelled'].contains(item.status)) continue;

      await _uploadSingleItemParallel(item);
      notifyListeners();
    }

    isUploading = false;
    await autoClearCache();
    notifyListeners();
  }

  // ================= FINAL PARALLEL UPLOAD =================
  Future<void> _uploadSingleItemParallel(UploadItem item) async {
    item.status = 'preparing';
    item.cancelToken = dio.CancelToken();
    notifyListeners();

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      item.status = 'error';
      notifyListeners();
      return;
    }

    File? encryptedFile;

    try {
      // ===== HASH =====
      final fileHash = await _getFileHash(item.file);

      final existingFile = await supabase
          .from('files')
          .select()
          .eq('hash', fileHash)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingFile != null) {
        item.progress = 1.0;
        item.status = 'exists';
        notifyListeners();
        return;
      }

      // ===== ENCRYPT =====
      final nonce = VaultService().generateNonce();
      final key = await VaultService().getSecretKey();

      encryptedFile = await _createEncryptedTempFile(item.file, key, nonce);
      if (encryptedFile == null) throw Exception("Encryption failed");

      item.status = 'initializing';
      notifyListeners();

      final dioClient = dio.Dio();
      final originalFileName = item.file.path.split(Platform.pathSeparator).last;
      final fileSize = await encryptedFile.length();

      int chunkSize = 2 * 1024 * 1024; // 2MB
      final totalChunks = (fileSize / chunkSize).ceil();
      const maxParallel = 3;

      item.uploadId = "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";

      int uploadedChunks = 0;
      Map<String, dynamic>? finalResponse;

      item.status = 'uploading';
      notifyListeners();

      Future<void> uploadChunk(int index) async {
        final start = index * chunkSize;
        final end = min(start + chunkSize, fileSize);
        final length = end - start;

        final raf = encryptedFile!.openSync();
        raf.setPositionSync(start);
        final chunkBytes = raf.readSync(length);
        raf.closeSync();

        final response = await dioClient.post(
          chunkUploadUrl,
          data: dio.FormData.fromMap({
            "file": dio.MultipartFile.fromBytes(chunkBytes, filename: originalFileName),
            "chunk_index": index,
            "total_chunks": totalChunks,
            "file_name": originalFileName,
            "upload_id": item.uploadId,
          }),
          cancelToken: item.cancelToken,
        );

        if (response.statusCode == null || response.statusCode! >= 300) {
          throw Exception("Chunk upload failed");
        }

        if (response.data is Map && response.data["status"] == "done") {
          finalResponse = Map<String, dynamic>.from(response.data);
        }

        uploadedChunks++;
        item.progress = uploadedChunks / totalChunks;
        notifyListeners();
      }

      List<Future> pool = [];

      for (int i = 0; i < totalChunks; i++) {
        if (item.status == 'cancelled') break;

        pool.add(uploadChunk(i));

        if (pool.length == maxParallel) {
          await Future.wait(pool);
          pool.clear();
        }
      }

      if (pool.isNotEmpty) {
        await Future.wait(pool);
      }

      if (finalResponse == null) {
        throw Exception("Final response missing from backend");
      }

      item.status = 'finalizing';
      notifyListeners();

      await _saveToSupabase(
        finalResponse!,
        originalFileName,
        fileSize,
        fileHash,
        base64Encode(nonce),
      );

      item.status = 'done';
    } on dio.DioException catch (e) {
      item.status = dio.CancelToken.isCancel(e) ? 'cancelled' : 'error';
    } catch (_) {
      item.status = 'error';
    } finally {
      if (encryptedFile != null && await encryptedFile.exists()) {
        await encryptedFile.delete();
      }

      notifyListeners();
    }
  }

  // ================= Encryption =================
  Future<File?> _createEncryptedTempFile(File originalFile, SecretKey key, List<int> nonce) async {
    try {
      final algorithm = AesGcm.with256bits();
      final fileBytes = await originalFile.readAsBytes();
      final secretBox = await algorithm.encrypt(fileBytes, secretKey: key, nonce: nonce);
      final encryptedBytes = secretBox.cipherText + secretBox.mac.bytes;

      final dir = await getTemporaryDirectory();
      final tempFile = File("${dir.path}/${originalFile.uri.pathSegments.last}.enc");

      await tempFile.writeAsBytes(encryptedBytes);
      return tempFile;
    } catch (_) {
      return null;
    }
  }

  Future<String> _getFileHash(File file) async {
    final stream = file.openRead();
    return (await sha256.bind(stream).first).toString();
  }

  Future<void> _saveToSupabase(Map data, String name, int size, String hash, String ivBase64) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    final String? folderIdToSave = (currentFolderId == 'root' || currentFolderId == '') ? null : currentFolderId;

    await supabase.from('files').insert({
      'user_id': user.id,
      'file_id': data['file_id'],
      'message_id': data['message_id'],
      'name': name,
      'type': _getFileType(name),
      'folder_id': folderIdToSave,
      'size': size,
      'hash': hash,
      'iv': ivBase64,
    });
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) return 'image';
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'aac', 'flac', 'm4a'].contains(ext)) return 'music';

    return 'document';
  }
}
