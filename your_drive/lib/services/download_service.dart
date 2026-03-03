import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../config/env.dart';
import 'vault_service.dart';

class DownloadService {
  static final Dio _dio = Dio();

  /// 📥 DOWNLOAD & DECRYPT FILE (supports chunked encryption)
  static Future<String> downloadFile(String messageId, String fileName) async {
    try {
      print("⬇️ Starting secure download for: $fileName");

      // 1️⃣ Get encryption metadata from Supabase
      final supabase = Supabase.instance.client;

      final fileData = await supabase
          .from('files')
          .select('iv, chunk_size, total_chunks')
          .eq('message_id', messageId)
          .single();

      final String? ivBase64 = fileData['iv'];
      if (ivBase64 == null || ivBase64.isEmpty) {
        throw Exception("Missing encryption IV");
      }

      final int chunkSize = fileData['chunk_size'] ?? 0;
      final int totalChunks = fileData['total_chunks'] ?? 1;

      // 2️⃣ Download encrypted bytes into memory
      final url = "${Env.backendBaseUrl}/api/file/$messageId";

      final Response<List<int>> response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode != 200 || response.data == null) {
        throw Exception("Download failed");
      }

      // 3️⃣ Decrypt locally (zero-knowledge)
      // Upload ALWAYS uses chunked encryption with nonce rotation,
      // even for single-chunk files, so always use chunked decryption.
      final List<int> decryptedBytes = await _decryptChunked(
        response.data!,
        ivBase64,
        chunkSize > 0 ? chunkSize : response.data!.length - 16, // fallback for legacy
        totalChunks,
      );

      // 4️⃣ Save to Gallery (images/videos) or Downloads (other files)
      final String ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';

      if (!fileName.contains('.')) {
        fileName = "$fileName.bin";
      }

      String savePath;

      if (_isImage(ext)) {
        savePath = await _saveImageToGallery(decryptedBytes, fileName);
      } else if (_isVideo(ext)) {
        savePath = await _saveVideoToGallery(decryptedBytes, fileName);
      } else {
        savePath = await _saveToDownloads(decryptedBytes, fileName);
      }

      print("✅ Decrypted file saved → $savePath");
      return savePath;
    } catch (e) {
      print("❌ Download Error: $e");
      throw Exception("Download failed: $e");
    }
  }

  // 🔐 AES-GCM CHUNKED DECRYPTION (per-chunk nonce rotation)
  static Future<List<int>> _decryptChunked(
    List<int> encryptedBytes,
    String ivBase64,
    int chunkSize,
    int totalChunks,
  ) async {
    final baseNonce = base64Decode(ivBase64);
    final secretKey = await VaultService().getSecretKey();
    final algorithm = AesGcm.with256bits();

    final output = BytesBuilder();
    int offset = 0;

    for (int i = 0; i < totalChunks; i++) {
      final int end = (i == totalChunks - 1)
          ? encryptedBytes.length
          : offset + chunkSize + 16; // +16 for MAC tag

      final chunk = encryptedBytes.sublist(offset, end);

      final macBytes = chunk.sublist(chunk.length - 16);
      final cipherText = chunk.sublist(0, chunk.length - 16);

      // Rotate nonce: overwrite last 4 bytes with chunk index
      final nonce = Uint8List.fromList(baseNonce);
      nonce[8] = (i >> 24) & 0xFF;
      nonce[9] = (i >> 16) & 0xFF;
      nonce[10] = (i >> 8) & 0xFF;
      nonce[11] = i & 0xFF;

      final decrypted = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );

      output.add(decrypted);
      offset = end;
    }

    return output.toBytes();
  }

  // ─── FILE TYPE HELPERS ───────────────────────────────────────
  static const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'};
  static const _videoExts = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', '3gp', 'wmv'};

  static bool _isImage(String ext) => _imageExts.contains(ext);
  static bool _isVideo(String ext) => _videoExts.contains(ext);

  // ─── SAVE IMAGE TO GALLERY ─────────────────────────────────
  static Future<String> _saveImageToGallery(List<int> bytes, String fileName) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Request permission
      final permitted = await _requestGalleryPermission();
      if (!permitted) throw Exception("Gallery permission denied");

      try {
        final asset = await PhotoManager.editor.saveImage(
          Uint8List.fromList(bytes),
          filename: fileName,
          title: fileName,
        );
        return "Gallery/${asset.title ?? fileName}";
      } catch (e) {
        print("⚠️ Gallery save failed, falling back to Downloads: $e");
      }
    }
    return _saveToDownloads(bytes, fileName);
  }

  // ─── SAVE VIDEO TO GALLERY ─────────────────────────────────
  static Future<String> _saveVideoToGallery(List<int> bytes, String fileName) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final permitted = await _requestGalleryPermission();
      if (!permitted) throw Exception("Gallery permission denied");

      // photo_manager needs a temp file for video
      final tempDir = await getTemporaryDirectory();
      final tempFile = File("${tempDir.path}/$fileName");
      await tempFile.writeAsBytes(bytes);

      try {
        final asset = await PhotoManager.editor.saveVideo(
          tempFile,
          title: fileName,
        );
        // Clean up temp file
        try { await tempFile.delete(); } catch (_) {}
        return "Gallery/${asset.title ?? fileName}";
      } catch (e) {
        // Clean up temp file on error too
        try { await tempFile.delete(); } catch (_) {}
        print("⚠️ Gallery save failed, falling back to Downloads: $e");
      }
    }
    return _saveToDownloads(bytes, fileName);
  }

  // ─── SAVE TO PUBLIC DOWNLOADS FOLDER ───────────────────────
  static Future<String> _saveToDownloads(List<int> bytes, String fileName) async {
    Directory? dir;

    if (Platform.isAndroid) {
      // Public Downloads folder — visible in file manager
      dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) {
        dir = await getExternalStorageDirectory();
      }
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    } else {
      dir = await getDownloadsDirectory();
    }

    if (dir == null) throw Exception("No writable directory");

    String savePath = "${dir.path}${Platform.pathSeparator}$fileName";
    savePath = _getUniquePath(savePath);

    final file = File(savePath);
    await file.writeAsBytes(bytes);
    return savePath;
  }

  // ─── REQUEST GALLERY / STORAGE PERMISSION ──────────────────
  static Future<bool> _requestGalleryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        // Android 13+ → granular media permissions
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        return photos.isGranted || videos.isGranted;
      } else if (sdkInt >= 29) {
        // Android 10-12 → scoped storage, no permission needed for MediaStore
        return true;
      } else {
        // Android 9 and below
        final status = await Permission.storage.request();
        return status.isGranted;
      }
    }

    return true; // Desktop
  }

  /// 🔄 DUPLICATE FILE NAME HANDLER
  static String _getUniquePath(String filePath) {
    File file = File(filePath);
    if (!file.existsSync()) return filePath;

    int count = 1;
    String newPath = filePath;

    final String dir = file.parent.path;
    final String name = file.uri.pathSegments.last;
    final String rawName =
        name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final String ext = name.contains('.') ? ".${name.split('.').last}" : "";

    while (file.existsSync()) {
      newPath = "$dir${Platform.pathSeparator}${rawName}_$count$ext";
      file = File(newPath);
      count++;
    }

    return newPath;
  }
}
