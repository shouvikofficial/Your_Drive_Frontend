import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for RootIsolateToken
import 'package:dio/dio.dart' as dio;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:convert/convert.dart';
import 'package:flutter/foundation.dart';

import '../services/saf_service.dart';
import '../config/env.dart';
import '../services/vault_service.dart';
import '../services/network_speed.dart';
import '../services/upload_strategy.dart';
import '../services/retry_helper.dart';
import '../services/resume_store.dart';
import '../workers/encryption_worker.dart';
import '../workers/hash_worker.dart';
import '../workers/media_thumbnail_worker.dart';


// ================= Upload Item =================
class UploadItem {
  final String id;
  final File? file;
  final String? name;
  final String? uri;
  final int? size;

  double progress;
  String status;
  String? uploadId;
  dio.CancelToken? cancelToken;

  UploadItem({
    this.file,
    this.name,
    this.uri,
    this.size,
    this.progress = 0.0,
    this.status = 'waiting',
  }) : id =
            DateTime.now().microsecondsSinceEpoch.toString() +
            Random().nextInt(1000).toString();
}

// ================= Upload Manager =================
class UploadManager extends ChangeNotifier {
  static final UploadManager _instance = UploadManager._internal();
  factory UploadManager() => _instance;
  UploadManager._internal();

  List<UploadItem> uploadQueue = [];
  bool isUploading = false;
  final ValueNotifier<bool> isUploadingNotifier = ValueNotifier(false);

  /// UI progress tracking
  int filesProcessed = 0;
  int totalFilesToProcess = 0;

  String currentFolderName = "My Drive";
  String? currentFolderId;

  final String chunkUploadUrl = "${Env.backendBaseUrl}/api/upload-chunk";
  final String cancelUploadUrl = "${Env.backendBaseUrl}/api/upload-cancel";

  /// RAM protection
  static const int _maxActiveChunks = 8;
  int _activeChunks = 0;

  DateTime _lastUiUpdate = DateTime.now();

  // ================= Add SAF File =================
  Future<UploadItem> addSafFile({
    required String uri,
    required String name,
    required int size,
    String? folderId,
    required String folderName,
  }) async {
    if (!isUploading) {
      currentFolderId = folderId;
      currentFolderName = folderName;
    }

    final item = UploadItem(name: name, uri: uri, size: size);
    uploadQueue.add(item);
    notifyListeners();
    return item;
  }
  Future<Uint8List?> _generateSafThumbnail(
  String uri,
  String fileName,
) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final tempPath = "${tempDir.path}/temp_$fileName";

    // 1️⃣ Read full SAF file
    final bytes = await SafService.readChunk(
      uri: uri,
      offset: 0,
      length: 1024 * 1024 * 10, // read first 10MB (enough for thumbnail)
    );

    if (bytes == null) return null;

    // 2️⃣ Save to temp file
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(bytes);

    Uint8List? thumb;

    final fileType = _getFileType(fileName);

    if (fileType == 'image') {
      thumb = await generateImageThumbnail(tempPath);
    } else if (fileType == 'video') {
      thumb = await generateVideoThumbnail(tempPath);
    }

    // 3️⃣ Delete temp file
    await tempFile.delete();

    return thumb;
  } catch (e) {
    debugPrint("SAF thumbnail error: $e");
    return null;
  }
}
  

  // ================= Start Batch Upload =================
  Future<void> startBatchUpload() async {
    if (isUploading) return;

    isUploading = true;
    isUploadingNotifier.value = true;
    filesProcessed = 0;

    final pendingFiles = uploadQueue
        .where((i) => !['done', 'exists', 'cancelled'].contains(i.status))
        .toList();

    totalFilesToProcess = pendingFiles.length;
    notifyListeners();

    const maxParallelFiles = 3;

    for (int i = 0; i < pendingFiles.length; i += maxParallelFiles) {
      final batch = pendingFiles.skip(i).take(maxParallelFiles);
      
      // Stagger start slightly to prevent CPU spikes
      await Future.wait(batch.map((item) async {
        await Future.delayed(Duration(milliseconds: Random().nextInt(200)));
        return _uploadSingleItemParallel(item);
      }));

      filesProcessed += batch.length;
      notifyListeners();
    }

    isUploading = false;
    isUploadingNotifier.value = false;
    notifyListeners();
  }

  // ================= Upload Additional Items (while a batch already runs) =================
  /// Uploads [items] in parallel batches without touching the [isUploading] flag.
  /// Safe to call while [startBatchUpload] is running.
  Future<void> uploadAdditionalItems(List<UploadItem> items) async {
    if (items.isEmpty) return;
    totalFilesToProcess += items.length;
    notifyListeners();

    const maxParallelFiles = 3;
    for (int i = 0; i < items.length; i += maxParallelFiles) {
      final batch = items.skip(i).take(maxParallelFiles);
      await Future.wait(batch.map((item) async {
        await Future.delayed(Duration(milliseconds: Random().nextInt(200)));
        return _uploadSingleItemParallel(item);
      }));
      filesProcessed += batch.length;
      notifyListeners();
    }
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
    uploadQueue.removeWhere(
      (item) => ['done', 'exists', 'cancelled', 'error'].contains(item.status),
    );
    notifyListeners();
  }

  // ================= Secure Nonce =================
  List<int> _buildChunkNonce(List<int> baseNonce, int index) {
    final nonce = List<int>.from(baseNonce);
    nonce[8] = (index >> 24) & 0xFF;
    nonce[9] = (index >> 16) & 0xFF;
    nonce[10] = (index >> 8) & 0xFF;
    nonce[11] = index & 0xFF;
    return nonce;
  }

// ================= Network Error Detection =================
bool _isNoInternetError(Object e) {
  if (e is SocketException) return true;
  if (e is dio.DioException) {
    if (e.error is SocketException) return true;
    if (e.type == dio.DioExceptionType.connectionError) return true;
    if (e.type == dio.DioExceptionType.connectionTimeout) return true;
    if (e.type == dio.DioExceptionType.sendTimeout) return true;
    if (e.type == dio.DioExceptionType.receiveTimeout) return true;
  }
  return false;
}

// ================= Upload Single File =================
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

  try {
    // ---------- File Info ----------
    final fileName =
        item.file?.path.split(Platform.pathSeparator).last ??
        item.name ??
        "file";

    final int fileSize =
        item.file != null ? await item.file!.length() : (item.size ?? 0);

    if (fileSize == 0) throw Exception("Empty file");

    // 🔥 START THUMBNAIL IN PARALLEL (DO NOT AWAIT)
    Future<Uint8List?>? thumbnailFuture;
    final fileType = _getFileType(fileName);

    if (item.file != null) {
  if (fileType == 'image') {
    thumbnailFuture =
        generateImageThumbnail(item.file!.path);
  } else if (fileType == 'video') {
    thumbnailFuture =
        generateVideoThumbnail(item.file!.path);
  }
} else if (item.uri != null) {
  // 🔥 SAF support
  thumbnailFuture =
      _generateSafThumbnail(item.uri!, fileName);
}

    // ---------- HASH ----------
    String fileHash;

    if (item.file != null) {
      // 🔥 Hash normal file in isolate
      fileHash = await compute(
        hashFileInIsolate,
        item.file!.path,
      );
    } else {
      // 🔥 Hash SAF in isolate (Lag Fixed)
      final rootToken = RootIsolateToken.instance;
      if (rootToken == null) {
        throw Exception("Cannot get RootIsolateToken");
      }

      fileHash = await compute(
        hashSafInIsolate,
        SafHashParams(
          token: rootToken,
          uri: item.uri!,
          fileSize: fileSize,
        ),
      );
    }

    // ---------- Dedup ----------
    final existing = await supabase
        .from('files')
        .select()
        .eq('hash', fileHash)
        .eq('user_id', user.id)
        .maybeSingle();

    if (existing != null) {
      item.progress = 1.0;
      item.status = 'exists';
      notifyListeners();
      return;
    }

    // 🔥 CONTINUE YOUR ENCRYPTION + UPLOAD BELOW THIS

      // ---------- Encryption ----------
      item.status = 'encrypting';
      notifyListeners();
      
      final key = await VaultService().getSecretKey();
      final baseNonce = VaultService().generateNonce();
      final keyBytes = await key.extractBytes(); // Extract once

      // ---------- Strategy ----------
      final isWifi = await NetworkSpeed.isWifi();
      final strategy = UploadStrategy.decide(fileSize: fileSize, isWifi: isWifi);

      // ---------- Stable Upload ID ----------
      item.uploadId ??= "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";
      int uploadedChunks = ResumeStore.getProgress(item.uploadId!);

      // ---------- Chunk setup ----------
      final chunkSize = strategy.chunkSize;
      final maxParallel = strategy.parallelChunks;
      final totalChunks = (fileSize / chunkSize).ceil();

      RandomAccessFile? raf;
      if (item.file != null) {
        raf = await item.file!.open();
      }

      item.status = 'uploading';
      notifyListeners();

      String? realMessageIdGlobal; // capture message_id from last chunk

      Future<void> processChunk(int index) async {
        if (item.status == 'cancelled') return;

        while (_activeChunks >= _maxActiveChunks) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        _activeChunks++;

        try {
          final start = index * chunkSize;
          final end = min(start + chunkSize, fileSize);
          final length = end - start;

          List<int>? plainBytes;

          if (raf != null) {
            await raf.setPosition(start);
            plainBytes = await raf.read(length);
          } else {
            plainBytes = await SafService.readChunk(
              uri: item.uri!,
              offset: start,
              length: length,
            );
          }

          if (plainBytes == null) throw Exception("Read failed");

          final nonce = _buildChunkNonce(baseNonce, index);

          final encryptedBytes = await compute(
            encryptChunkInIsolate,
            EncryptParams(
              bytes: plainBytes,
              keyBytes: keyBytes,
              nonce: nonce,
            ),
          );

          final response = await RetryHelper.retry(() => dio.Dio().post(
                chunkUploadUrl,
                data: dio.FormData.fromMap({
                  "file": dio.MultipartFile.fromBytes(
                    encryptedBytes,
                    filename: fileName,
                  ),
                  "chunk_index": index,
                  "total_chunks": totalChunks,
                  "file_name": fileName,
                  "upload_id": item.uploadId,
                }),
                cancelToken: item.cancelToken,
              ));

          if (response.statusCode == null || response.statusCode! >= 300) {
            throw Exception("Chunk upload failed");
          }

          // ✅ Last Chunk Logic
          if (response.data["status"] == "done") {
            final realMessageId = response.data["message_id"];
            if (realMessageId == null) {
              throw Exception("Backend did not return message_id");
            }
            realMessageIdGlobal = realMessageId.toString(); // store for thumbnail

            await _saveToSupabase(
              {
                "file_id": item.uploadId,
                "message_id": realMessageId,
              },
              fileName,
              fileSize,
              fileHash,
              base64Encode(baseNonce),
              strategy.chunkSize,
              totalChunks,
            );
          }

          uploadedChunks++;
          await ResumeStore.saveProgress(item.uploadId!, uploadedChunks);

          item.progress = uploadedChunks / totalChunks;

          // 🔥 Throttle UI updates
          final now = DateTime.now();
          if (now.difference(_lastUiUpdate).inMilliseconds > 300 ||
              uploadedChunks == totalChunks) {
            _lastUiUpdate = now;
            notifyListeners();
          }
        } finally {
          _activeChunks--;
        }
      }

      List<Future> pool = [];

      for (int i = uploadedChunks; i < totalChunks; i++) {
        if (item.status == 'cancelled') break;

        pool.add(processChunk(i));

        if (pool.length == maxParallel) {
          await Future.wait(pool);
          pool.clear();
        }
      }

      if (pool.isNotEmpty) await Future.wait(pool);

      await raf?.close();

      // 🔐 Upload thumbnail AFTER all chunks finished
if (thumbnailFuture != null) {
  try {
    final thumbBytes = await thumbnailFuture;

    if (thumbBytes != null) {
      final thumbNonce = VaultService().generateNonce();
      final algorithm = AesGcm.with256bits();

      final secretBox = await algorithm.encrypt(
        thumbBytes,
        secretKey: key,
        nonce: thumbNonce,
      );

      final encryptedThumb =
          secretBox.cipherText + secretBox.mac.bytes;

      await _uploadEncryptedThumbnail(
        realMessageIdGlobal ?? item.uploadId!,
        encryptedThumb,
        thumbNonce,
      );

      debugPrint("Thumbnail uploaded successfully");
    }
  } catch (e) {
    debugPrint("Thumbnail upload failed: $e");
  }
}
      
      // Cleanup
      await ResumeStore.clear(item.uploadId!);
      item.progress = 1.0;
item.status = 'done';
notifyListeners();



    } on dio.DioException catch (e) {
      item.status = dio.CancelToken.isCancel(e)
          ? 'cancelled'
          : (_isNoInternetError(e) ? 'no_internet' : 'error');
    } catch (e) {
      debugPrint("Upload error: $e");
      item.status = _isNoInternetError(e) ? 'no_internet' : 'error';
    } finally {
      notifyListeners();
    }
  }

  // ================= Save to Supabase =================
  Future<void> _saveToSupabase(
    Map data,
    String name,
    int size,
    String hash,
    String ivBase64,
    int chunkSize,
    int totalChunks,
  ) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    final String? folderIdToSave =
        (currentFolderId == 'root' || currentFolderId == '')
            ? null
            : currentFolderId;

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
      'chunk_size': chunkSize,
      'total_chunks': totalChunks,
    });
  }
  Future<void> _uploadEncryptedThumbnail(
  String fileId,
  List<int> encryptedBytes,
  List<int> nonce,
) async {
  try {
    final supabase = Supabase.instance.client;

    final response = await dio.Dio().post(
      "${Env.backendBaseUrl}/api/upload-thumbnail",
      data: dio.FormData.fromMap({
        "file": dio.MultipartFile.fromBytes(
          encryptedBytes,
          filename: "thumb_$fileId.enc", // unique filename per upload
        ),
        "upload_id": fileId,
      }),
    );

    if (response.statusCode == null || response.statusCode! >= 300) {
      debugPrint("Thumbnail backend error: ${response.statusCode} ${response.data}");
      return;
    }

    final tgThumbMessageId = response.data["message_id"];
    if (tgThumbMessageId == null) {
      debugPrint("Thumbnail upload: backend returned no message_id");
      return;
    }

    await supabase.from('files').update({
      'thumbnail_id': tgThumbMessageId,
      'thumbnail_iv': base64Encode(nonce),
    }).eq('message_id', int.tryParse(fileId) ?? fileId);

    debugPrint("Thumbnail saved to Supabase: $tgThumbMessageId");
  } on dio.DioException catch (e) {
    debugPrint("Thumbnail DioException: ${e.response?.statusCode} ${e.response?.data} ${e.message}");
  } catch (e) {
    debugPrint("Thumbnail upload error: $e");
  }
}

  // ================= File Type Helper =================
  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) return 'image';
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'aac', 'flac', 'm4a'].contains(ext)) return 'music';
    return 'document';
  }
}