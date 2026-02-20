import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as dio;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:convert/convert.dart';
import '../services/saf_service.dart';
import '../config/env.dart';
import '../services/vault_service.dart';
import '../services/network_speed.dart';
import '../services/upload_strategy.dart';
import '../services/retry_helper.dart';
import '../services/resume_store.dart';


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

  /// UI progress tracking (RESTORED)
  int filesProcessed = 0;
  int totalFilesToProcess = 0;

  String currentFolderName = "My Drive";
  String? currentFolderId;

  final String chunkUploadUrl = "${Env.backendBaseUrl}/api/upload-chunk";
  final String cancelUploadUrl = "${Env.backendBaseUrl}/api/upload-cancel";

  /// RAM protection
  static const int _maxActiveChunks = 8;
  int _activeChunks = 0;


  // ================= Add SAF File =================
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
      UploadItem(name: name, uri: uri, size: size),
    );

    notifyListeners();
  }


  // ================= Start Batch Upload =================
  Future<void> startBatchUpload() async {
    if (isUploading) return;

    isUploading = true;
    filesProcessed = 0;

    final pendingFiles = uploadQueue
        .where((i) => !['done', 'exists', 'cancelled'].contains(i.status))
        .toList();

    totalFilesToProcess = pendingFiles.length;
    notifyListeners();

    const maxParallelFiles = 3;

    for (int i = 0; i < pendingFiles.length; i += maxParallelFiles) {
      final batch = pendingFiles.skip(i).take(maxParallelFiles);
      await Future.wait(batch.map(_uploadSingleItemParallel));

      filesProcessed += batch.length;
      notifyListeners();
    }

    isUploading = false;
    notifyListeners();
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

      // ---------- HASH ----------
      Digest hash;

      if (item.file != null) {
        hash = await sha256.bind(item.file!.openRead()).first;
      } else {
        const int hashChunk = 1024 * 1024;
        int offset = 0;

        final sink = AccumulatorSink<Digest>();
        final input = sha256.startChunkedConversion(sink);

        while (offset < fileSize) {
          final readLen =
              (offset + hashChunk > fileSize) ? fileSize - offset : hashChunk;

          final bytes = await SafService.readChunk(
            uri: item.uri!,
            offset: offset,
            length: readLen,
          );

          if (bytes == null) throw Exception("SAF read failed");

          input.add(bytes);
          offset += readLen;
        }

        input.close();
        hash = sink.events.single;
      }

      final fileHash = hash.toString();

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

      // ---------- Encryption ----------
      final algorithm = AesGcm.with256bits();
      final key = await VaultService().getSecretKey();
      final baseNonce = VaultService().generateNonce();

      // ---------- Strategy ----------
      final isWifi = await NetworkSpeed.isWifi();
      final strategy =
          UploadStrategy.decide(fileSize: fileSize, isWifi: isWifi);

      // ---------- Stable Upload ID ----------
      item.uploadId ??=
          "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";

      int uploadedChunks = ResumeStore.getProgress(item.uploadId!);

      // ---------- Small file direct upload ----------
      if (!strategy.useChunking) {
        final bytes = item.file != null
            ? await item.file!.readAsBytes()
            : await SafService.readChunk(
                uri: item.uri!,
                offset: 0,
                length: fileSize,
              );

        if (bytes == null) throw Exception("Read failed");

 final secretBox =
    await algorithm.encrypt(bytes, secretKey: key, nonce: baseNonce);

final res = await RetryHelper.retry(() => dio.Dio().post(
      chunkUploadUrl,
      data: dio.FormData.fromMap({
        "file": dio.MultipartFile.fromBytes(
          secretBox.cipherText + secretBox.mac.bytes,
          filename: fileName,
        ),
        "chunk_index": 0,
        "total_chunks": 1,
        "file_name": fileName,
        "upload_id": item.uploadId,
      }),
      cancelToken: item.cancelToken,
    ));

// ⭐ GET REAL TELEGRAM MESSAGE ID FROM BACKEND
final realMessageId = res.data["message_id"];

await _saveToSupabase(
  {
    "file_id": item.uploadId,
    "message_id": realMessageId, // ✅ FIXED
  },
  fileName,
  fileSize,
  fileHash,
  base64Encode(baseNonce),
  strategy.chunkSize,
  1, // ✅ total_chunks = 1 for direct upload
);


        item.progress = 1.0;
        item.status = 'done';
        notifyListeners();
        return;
      }

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

          final secretBox =
              await algorithm.encrypt(plainBytes, secretKey: key, nonce: nonce);

       final encryptedBytes = secretBox.cipherText + secretBox.mac.bytes;

final response = await RetryHelper.retry(() => dio.Dio().post(
      chunkUploadUrl,
      data: dio.FormData.fromMap({
        "file": dio.MultipartFile.fromBytes(
          encryptedBytes,
          filename: fileName,
        ),
        "chunk_index": index,
        "total_chunks": totalChunks,
        "file_name": fileName,   // ⭐ REQUIRED FOR FASTAPI
        "upload_id": item.uploadId,
      }),
      cancelToken: item.cancelToken,
    ));

if (response.statusCode == null || response.statusCode! >= 300) {
  throw Exception("Chunk upload failed");
}

// ✅ If this is LAST chunk, backend should return real message_id
if (response.data["status"] == "done") {

  final realMessageId = response.data["message_id"];

  if (realMessageId == null) {
    throw Exception("Backend did not return message_id");
  }

  await _saveToSupabase(
    {
      "file_id": item.uploadId,
      "message_id": realMessageId,  // ✅ REAL TELEGRAM ID
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
          notifyListeners();
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
      await ResumeStore.clear(item.uploadId!);



      item.progress = 1.0;
      item.status = 'done';
    } on dio.DioException catch (e) {
      item.status = dio.CancelToken.isCancel(e) ? 'cancelled' : 'error';
    } catch (e) {
      debugPrint("Upload error: $e");
      item.status = 'error';
    } finally {
      notifyListeners();
    }
  }


  // ================= Save to Supabase =================
  Future<void> _saveToSupabase(
      Map data, String name, int size, String hash, String ivBase64,int chunkSize, int totalChunks,) async {
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


  // ================= File Type Helper =================
  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();

    if (['jpg','jpeg','png','gif','webp','heic'].contains(ext)) return 'image';
    if (['mp4','mov','avi','mkv','webm'].contains(ext)) return 'video';
    if (['mp3','wav','aac','flac','m4a'].contains(ext)) return 'music';

    return 'document';
  }
}
