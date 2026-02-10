import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cryptography/cryptography.dart';
import '../config/env.dart';
import 'vault_service.dart';

class DownloadService {
  static final Dio _dio = Dio();

  /// 📥 DOWNLOAD & DECRYPT FILE
  static Future<String> downloadFile(String messageId, String fileName) async {
    try {
      print("⬇️ Starting secure download for: $fileName");

      // 1️⃣ Get IV from Supabase
      final supabase = Supabase.instance.client;

      final fileData = await supabase
          .from('files')
          .select('iv')
          .eq('message_id', messageId)
          .single();

      final String? ivBase64 = fileData['iv'];
      if (ivBase64 == null || ivBase64.isEmpty) {
        throw Exception("Missing encryption IV");
      }

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
      final decryptedBytes = await _decryptData(response.data!, ivBase64);

      // 4️⃣ Get safe directory
      final Directory? dir = await _getDownloadDirectory();
      if (dir == null) throw Exception("No writable directory");

      // 5️⃣ Ensure filename has extension
      if (!fileName.contains('.')) {
        fileName = "$fileName.bin";
      }

      // 6️⃣ Handle duplicates
      String savePath = "${dir.path}${Platform.pathSeparator}$fileName";
      savePath = _getUniquePath(savePath);

      // 7️⃣ Save decrypted file
      final file = File(savePath);
      await file.writeAsBytes(decryptedBytes);

      print("✅ Decrypted file saved → $savePath");
      return savePath;
    } catch (e) {
      print("❌ Download Error: $e");
      throw Exception("Download failed: $e");
    }
  }

  // 🔐 AES-GCM DECRYPTION
  static Future<List<int>> _decryptData(List<int> encryptedData, String ivBase64) async {
    final nonce = base64Decode(ivBase64);
    final secretKey = await VaultService().getSecretKey();
    final algorithm = AesGcm.with256bits();

    if (encryptedData.length < 16) {
      throw Exception("Invalid encrypted data");
    }

    final macBytes = encryptedData.sublist(encryptedData.length - 16);
    final ciphertext = encryptedData.sublist(0, encryptedData.length - 16);

    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    return await algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );
  }

  /// 📂 SAFE CROSS-PLATFORM DIRECTORY
  static Future<Directory?> _getDownloadDirectory() async {
    // Android & iOS → safe app storage (no permission issues)
    if (Platform.isAndroid || Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }

    // Desktop platforms
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return await getDownloadsDirectory();
    }

    return null;
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
