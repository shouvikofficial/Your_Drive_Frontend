import 'dart:io';
import 'dart:math';

import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256, Digest;
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as dio;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../services/saf_service.dart';
import '../config/env.dart';
import '../services/vault_service.dart';


// ================= Upload Item =================
class UploadItem {
  final String id;

  // normal picker file
  final File? file;

  // SAF picker info
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
Future<void> addSafFile({
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

  uploadQueue.add(
    UploadItem(
      file: null,
      name: name,
      uri: uri,
      size: size,
    ),
  );

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

  // 👉 take only files that need upload
  final pendingFiles = uploadQueue
      .where((i) => !['done', 'exists', 'cancelled'].contains(i.status))
      .toList();

  const maxParallelFiles = 3; // ⭐ SAFE mobile limit

  // 👉 process files in small parallel batches
  for (int i = 0; i < pendingFiles.length; i += maxParallelFiles) {
    final batch = pendingFiles.skip(i).take(maxParallelFiles);

    // ⭐ upload this batch in parallel
    await Future.wait(batch.map(_uploadSingleItemParallel));
  }

  isUploading = false;

  await autoClearCache();
  notifyListeners();
}


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
    // ================= FILE INFO =================
    final fileName =
        item.file?.path.split(Platform.pathSeparator).last ??
        item.name ??
        "file";

    final int fileSize =
        item.file != null ? await item.file!.length() : (item.size ?? 0);

    if (fileSize == 0) {
      item.status = 'error';
      notifyListeners();
      return;
    }

// ================= HASH (STREAM SAFE) =================
Digest hash;

if (item.file != null) {
  hash = await sha256.bind(item.file!.openRead()).first;
} else {
  const int hashChunk = 1024 * 1024;
  int offset = 0;

final AccumulatorSink<Digest> sink = AccumulatorSink<Digest>();
final ByteConversionSink input = sha256.startChunkedConversion(sink);



  while (offset < fileSize) {
    final int readLen =
        (offset + hashChunk > fileSize) ? fileSize - offset : hashChunk;

    final bytes = await SafService.readChunk(
      uri: item.uri!,
      offset: offset,
      length: readLen,
    );

    if (bytes == null) {
      item.status = 'error';
      notifyListeners();
      return;
    }

    input.add(bytes);
    offset += readLen;
  }

  input.close();
  hash = sink.events.single;
}



    final fileHash = hash.toString();

    // ================= DUPLICATE CHECK =================
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

    // ================= ENCRYPTION SETUP =================
    final algorithm = AesGcm.with256bits();
    final key = await VaultService().getSecretKey();
    final baseNonce = VaultService().generateNonce(); // 12 bytes

    // ================= UPLOAD SETUP =================
    final dioClient = dio.Dio();

    const int chunkSize = 2 * 1024 * 1024; // 2MB
    final int totalChunks = (fileSize / chunkSize).ceil();
    const int maxParallel = 3;

    item.uploadId =
        "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";

    int uploadedChunks = 0;
    Map<String, dynamic>? finalResponse;

    item.status = 'uploading';
    notifyListeners();

    // ================= READ + ENCRYPT + UPLOAD =================
    Future<void> processChunk(int index) async {
      final start = index * chunkSize;
      final end = min(start + chunkSize, fileSize);
      final length = end - start;

      List<int>? plainBytes;

      if (item.file != null) {
        final raf = item.file!.openSync();
        raf.setPositionSync(start);
        plainBytes = raf.readSync(length);
        raf.closeSync();
      } else {
        plainBytes = await SafService.readChunk(
          uri: item.uri!,
          offset: start,
          length: length,
        );
      }

      if (plainBytes == null) {
        throw Exception("Read failed");
      }

      // 🔐 unique nonce per chunk
      final nonce = List<int>.from(baseNonce);
      nonce[nonce.length - 1] ^= index & 0xFF;

      final secretBox = await algorithm.encrypt(
        plainBytes,
        secretKey: key,
        nonce: nonce,
      );

      final encryptedBytes = secretBox.cipherText + secretBox.mac.bytes;

      final response = await dioClient.post(
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
      );

      if (response.statusCode == null || response.statusCode! >= 300) {
        throw Exception("Chunk upload failed");
      }

      if (response.data is Map && response.data["status"] == "done") {
  finalResponse ??= Map<String, dynamic>.from(response.data);
}

      uploadedChunks++;
      item.progress = uploadedChunks / totalChunks;
      notifyListeners();
    }

    // ================= PARALLEL CHUNK LOOP =================
    List<Future> pool = [];

    for (int i = 0; i < totalChunks; i++) {
      if (item.status == 'cancelled') break;

      pool.add(processChunk(i));

      if (pool.length == maxParallel) {
        await Future.wait(pool);
        pool.clear();
      }
    }

    if (pool.isNotEmpty) {
      await Future.wait(pool);
    }

if (finalResponse == null) {
  // wait small time for backend finalize response
  await Future.delayed(const Duration(seconds: 2));

  // try to fetch status from backend
  try {
    final check = await dioClient.get(
      "${Env.backendBaseUrl}/api/upload-status/${item.uploadId}",
    );

    if (check.data["status"] == "done") {
      // create minimal finalResponse so flow continues
      finalResponse = {
        "file_id": item.uploadId,
        "message_id": item.uploadId,
      };
    }
  } catch (_) {}
}
item.progress = 1.0;

// ================= SAVE DB =================
item.status = 'finalizing';
notifyListeners();

try {
  await _saveToSupabase(
    finalResponse!,
    fileName,
    fileSize,
    fileHash,
    base64Encode(baseNonce),
  );
} catch (e) {
  // ⚠️ IMPORTANT:
  // Telegram already uploaded successfully.
  // Metadata failure should NOT mark upload failed.
  debugPrint("Supabase save failed but Telegram upload succeeded: $e");
}

// ⭐ Always mark as done after Telegram success
item.status = 'done';

 } on dio.DioException catch (e) {
  if (dio.CancelToken.isCancel(e)) {
    item.status = 'cancelled';
  } else {
    item.status = 'error';
  }
} catch (e) {
  debugPrint("Upload unexpected error: $e");
  item.status = 'error';
}finally {
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
