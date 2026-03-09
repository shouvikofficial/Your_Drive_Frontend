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
import 'package:shared_preferences/shared_preferences.dart';

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

  // Resume fields — persisted so we can continue from exact chunk
  String? baseNonceB64;   // base64-encoded baseNonce
  String? fileHash;
  int? chunkSize;
  int? totalChunks;

  UploadItem({
    String? id,
    this.file,
    this.name,
    this.uri,
    this.size,
    this.progress = 0.0,
    this.status = 'waiting',
    this.uploadId,
    this.baseNonceB64,
    this.fileHash,
    this.chunkSize,
    this.totalChunks,
  }) : id = id ??
            (DateTime.now().microsecondsSinceEpoch.toString() +
            Random().nextInt(1000).toString());

  /// Serialize for disk persistence
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'uri': uri,
    'size': size,
    'filePath': file?.path,
    'progress': progress,
    'status': status,
    'uploadId': uploadId,
    'baseNonceB64': baseNonceB64,
    'fileHash': fileHash,
    'chunkSize': chunkSize,
    'totalChunks': totalChunks,
  };

  /// Restore from disk
  factory UploadItem.fromJson(Map<String, dynamic> json) {
    final path = json['filePath'] as String?;
    return UploadItem(
      id: json['id'] as String?,
      file: (path != null && File(path).existsSync()) ? File(path) : null,
      name: json['name'] as String?,
      uri: json['uri'] as String?,
      size: json['size'] as int?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'waiting',
      uploadId: json['uploadId'] as String?,
      baseNonceB64: json['baseNonceB64'] as String?,
      fileHash: json['fileHash'] as String?,
      chunkSize: json['chunkSize'] as int?,
      totalChunks: json['totalChunks'] as int?,
    );
  }
}

// ================= Upload Manager =================
class UploadManager extends ChangeNotifier {
  static final UploadManager _instance = UploadManager._internal();
  factory UploadManager() => _instance;
  UploadManager._internal();

  List<UploadItem> uploadQueue = [];
  bool isUploading = false;
  final ValueNotifier<bool> isUploadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> hasPausedNotifier = ValueNotifier(false);

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

  // ================= Throttle & Debounce =================
  DateTime _lastUiUpdate = DateTime.now();
  Timer? _persistDebounce;
  bool _persistScheduled = false;

  /// Throttled notify — prevents more than ~1 rebuild per 800ms during uploads
  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastUiUpdate).inMilliseconds > 800) {
      _lastUiUpdate = now;
      notifyListeners();
    }
  }

  /// Debounced persist — batches disk writes, max once per 5s during upload
  void _debouncedPersist() {
    if (_persistScheduled) return;
    _persistScheduled = true;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 5), () {
      _persistScheduled = false;
      _persistQueue();
    });
  }

  /// Immediate persist + notify — for important state changes (done, error, cancel)
  void _immediateSync() {
    _lastUiUpdate = DateTime.now();
    notifyListeners();
    _persistDebounce?.cancel();
    _persistScheduled = false;
    _persistQueue();
  }

  static const String _queueKey = 'upload_queue';
  static const String _folderIdKey = 'upload_folder_id';
  static const String _folderNameKey = 'upload_folder_name';

  // ================= Queue Persistence =================
  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = uploadQueue
          .where((i) => !['done', 'exists', 'cancelled'].contains(i.status))
          .map((i) => jsonEncode(i.toJson()))
          .toList();
      await prefs.setStringList(_queueKey, jsonList);
      await prefs.setString(_folderNameKey, currentFolderName);
      if (currentFolderId != null) {
        await prefs.setString(_folderIdKey, currentFolderId!);
      }
      _updatePausedNotifier();
    } catch (e) {
      debugPrint('[UploadManager] Persist error: $e');
    }
  }

  void _updatePausedNotifier() {
    final hasPaused = uploadQueue.any((i) => i.status == 'paused');
    if (hasPausedNotifier.value != hasPaused) {
      hasPausedNotifier.value = hasPaused;
    }
  }

  /// Restore queue from disk. Call once at app startup.
  Future<void> restoreQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_queueKey);
      if (jsonList == null || jsonList.isEmpty) return;

      currentFolderName = prefs.getString(_folderNameKey) ?? 'My Drive';
      currentFolderId = prefs.getString(_folderIdKey);

      final restored = <UploadItem>[];
      for (final raw in jsonList) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final item = UploadItem.fromJson(map);

          // Mark items that were actively processing as paused
          // Keep uploadId + resume fields intact for true resume!
          if (['uploading', 'preparing', 'encrypting', 'initializing', 'finalizing']
              .contains(item.status)) {
            item.status = 'paused';
          }
          // Also treat waiting items as paused (they were queued but not started)
          if (item.status == 'waiting') {
            item.status = 'paused';
          }
          // Skip items that can't be re-read (no URI and no valid File)
          if (item.uri == null && item.file == null) continue;

          restored.add(item);
        } catch (_) {}
      }

      if (restored.isNotEmpty) {
        uploadQueue = restored;
        debugPrint('[UploadManager] Restored ${restored.length} items from disk (paused)');
        notifyListeners();
        _updatePausedNotifier();
      }
    } catch (e) {
      debugPrint('[UploadManager] Restore error: $e');
    }
  }

  /// Resume all paused/interrupted/waiting/error items
  Future<void> resumeAll() async {
    final resumable = uploadQueue
        .where((i) => ['paused', 'interrupted', 'waiting', 'error', 'no_internet'].contains(i.status))
        .toList();
    if (resumable.isEmpty) return;

    // Reset status to waiting so the upload engine picks them up
    for (final item in resumable) {
      item.status = 'waiting';
    }
    notifyListeners();
    _updatePausedNotifier();
    await _persistQueue();

    // Start upload
    if (!isUploading) {
      startBatchUpload();
    } else {
      uploadAdditionalItems(resumable);
    }
  }

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
    _persistQueue();
    return item;
  }

  // ================= Add Native File (Camera / Local) =================
  Future<UploadItem> addNativeFile({
    required File file,
    String? folderId,
    required String folderName,
  }) async {
    if (!isUploading) {
      currentFolderId = folderId;
      currentFolderName = folderName;
    }

    final name = file.path.split(Platform.pathSeparator).last;
    final size = await file.length();

    final item = UploadItem(file: file, name: name, size: size);
    uploadQueue.add(item);
    notifyListeners();
    _persistQueue();
    return item;
  }
  Future<Uint8List?> _generateSafThumbnail(
  String uri,
  String fileName,
) async {
  try {
    final fileType = _getFileType(fileName);

    // 🎬 For videos: use native Android MediaMetadataRetriever
    // which reads directly from content:// URI — no need to copy
    // the entire file (fixes truncated-file thumbnail failure).
    if (fileType == 'video') {
      final thumb = await SafService.getVideoThumbnail(uri);
      if (thumb != null) return thumb;
      debugPrint("SAF native video thumbnail returned null, skipping");
      return null;
    }

    // 🖼️ For images: read first 10MB (always enough for images)
    final tempDir = await getTemporaryDirectory();
    final tempPath = "${tempDir.path}/temp_$fileName";

    final bytes = await SafService.readChunk(
      uri: uri,
      offset: 0,
      length: 1024 * 1024 * 10,
    );

    if (bytes == null) return null;

    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(bytes);

    final thumb = await generateImageThumbnail(tempPath);

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
    _updatePausedNotifier();

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
    _persistQueue(); // save final state
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
      
      // Auto-clear cancelled item after 1 second
      Future.delayed(const Duration(seconds: 1), () {
        if (uploadQueue.contains(item)) removeFile(item);
      });
    } else if (item.status == 'waiting') {
      removeFile(item);
    }
  }

  void removeFile(UploadItem item) {
    uploadQueue.remove(item);
    notifyListeners();
    _persistQueue();
  }

  void clearCompleted() {
    uploadQueue.removeWhere(
      (item) => ['done', 'exists', 'cancelled', 'error'].contains(item.status),
    );
    notifyListeners();
    _persistQueue();
  }

  void clearAll() {
    for (final item in uploadQueue) {
      if (item.uploadId != null) {
        ResumeStore.clear(item.uploadId!);
      }
    }
    uploadQueue.clear();
    notifyListeners();
    _persistQueue();
  }

  /// Cancel every in-flight upload, clear queue, and reset all state.
  /// Call this on logout to prevent uploads from leaking to another account.
  void cancelAllAndReset() {
    // 1. Cancel every active upload's network requests
    for (final item in uploadQueue) {
      item.cancelToken?.cancel("User logged out");
      if (item.uploadId != null) {
        ResumeStore.clear(item.uploadId!);
      }
    }

    // 2. Clear queue
    uploadQueue.clear();

    // 3. Reset state flags
    isUploading = false;
    isUploadingNotifier.value = false;
    hasPausedNotifier.value = false;
    filesProcessed = 0;
    totalFilesToProcess = 0;
    _activeChunks = 0;
    _persistDebounce?.cancel();
    _persistScheduled = false;

    notifyListeners();
    _persistQueue();
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
  _throttledNotify();

  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    item.status = 'error';
    _immediateSync();
    return;
  }

  // Capture user ID at start — used to guard against account switch mid-upload
  final String startUserId = user.id;

  try {
    // ---------- File Info ----------
    final fileName =
        item.file?.path.split(Platform.pathSeparator).last ??
        item.name ??
        "file";

    final int fileSize =
        item.file != null ? await item.file!.length() : (item.size ?? 0);

    if (fileSize == 0) throw Exception("Empty file");

    // Check if this is a RESUME (has saved encryption context from previous run)
    final bool isResume = item.baseNonceB64 != null &&
        item.fileHash != null &&
        item.uploadId != null &&
        item.chunkSize != null &&
        item.totalChunks != null;

    // 🔥 START THUMBNAIL IN PARALLEL (DO NOT AWAIT) — skip on resume
    Future<Uint8List?>? thumbnailFuture;
    final fileType = _getFileType(fileName);

    if (!isResume) {
      if (item.file != null) {
        if (fileType == 'image') {
          thumbnailFuture = generateImageThumbnail(item.file!.path);
        } else if (fileType == 'video') {
          thumbnailFuture = generateVideoThumbnail(item.file!.path);
        }
      } else if (item.uri != null) {
        thumbnailFuture = _generateSafThumbnail(item.uri!, fileName);
      }
    }

    // ---------- HASH (skip on resume) ----------
    String fileHash;

    if (isResume) {
      fileHash = item.fileHash!;
      debugPrint('[UploadManager] Resuming ${item.name} — skipping hash/dedup');
    } else {
      if (item.file != null) {
        fileHash = await compute(hashFileInIsolate, item.file!.path);
      } else {
        final rootToken = RootIsolateToken.instance;
        if (rootToken == null) throw Exception("Cannot get RootIsolateToken");
        fileHash = await compute(
          hashSafInIsolate,
          SafHashParams(token: rootToken, uri: item.uri!, fileSize: fileSize),
        );
      }

      // ---------- Dedup (skip on resume) ----------
      final existing = await supabase
          .from('files')
          .select()
          .eq('hash', fileHash)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing != null) {
        item.progress = 1.0;
        item.status = 'exists';
        _immediateSync();
        
        // Auto-clear item after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (uploadQueue.contains(item)) removeFile(item);
        });
        return;
      }
    }

    // ---------- Encryption context ----------
      item.status = 'encrypting';
      _throttledNotify();
      
      final key = await VaultService().getSecretKey();
      final keyBytes = await key.extractBytes();

      // Reuse saved nonce on resume, or generate fresh one
      List<int> baseNonce;
      if (isResume) {
        baseNonce = base64Decode(item.baseNonceB64!);
      } else {
        baseNonce = VaultService().generateNonce();
      }

      // ---------- Strategy ----------
      final isWifi = await NetworkSpeed.isWifi();
      final strategy = UploadStrategy.decide(fileSize: fileSize, isWifi: isWifi);

      // ---------- Stable Upload ID ----------
      item.uploadId ??= "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";
      int uploadedChunks = ResumeStore.getProgress(item.uploadId!);

      // ---------- Chunk setup ----------
      final chunkSize = isResume ? item.chunkSize! : strategy.chunkSize;
      final maxParallel = strategy.parallelChunks;
      final totalChunks = isResume ? item.totalChunks! : (fileSize / chunkSize).ceil();

      // Save resume context on item for persistence
      item.baseNonceB64 = base64Encode(baseNonce);
      item.fileHash = fileHash;
      item.chunkSize = chunkSize;
      item.totalChunks = totalChunks;
      _debouncedPersist(); // Save resume context (debounced — not blocking)

      RandomAccessFile? raf;
      if (item.file != null) {
        raf = await item.file!.open();
      }

      item.status = 'uploading';
      item.progress = totalChunks > 0 ? uploadedChunks / totalChunks : 0.0;
      _throttledNotify();

      debugPrint('[UploadManager] ${isResume ? "RESUMING" : "Starting"} ${item.name}: chunk $uploadedChunks/$totalChunks');

      String? realMessageIdGlobal;

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
              chunkSize,
              totalChunks,
              startUserId,
            );
          }

          uploadedChunks++;
          ResumeStore.saveProgress(item.uploadId!, uploadedChunks); // fire-and-forget

          item.progress = uploadedChunks / totalChunks;

          // 🔥 Throttled UI update — shared across all parallel files
          _throttledNotify();
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
      item.baseNonceB64 = null;
      item.fileHash = null;
      item.chunkSize = null;
      item.totalChunks = null;
      item.progress = 1.0;
      item.status = 'done';
      _immediateSync(); // important state change — notify + persist now

      // Auto-clear item after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (uploadQueue.contains(item)) removeFile(item);
      });

    } on dio.DioException catch (e) {
      item.status = dio.CancelToken.isCancel(e)
          ? 'cancelled'
          : (_isNoInternetError(e) ? 'no_internet' : 'error');
      _immediateSync();
    } catch (e) {
      debugPrint("Upload error: $e");
      item.status = _isNoInternetError(e) ? 'no_internet' : 'error';
      _immediateSync();
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
    String expectedUserId,
  ) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    // Guard: abort if user changed (logged out or switched accounts)
    if (user == null || user.id != expectedUserId) {
      debugPrint('[UploadManager] User changed — aborting save to Supabase');
      return;
    }

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