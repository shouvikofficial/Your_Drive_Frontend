import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../config/env.dart';

class DownloadService {
  static final Dio _dio = Dio();

  /// 📥 DOWNLOAD FILE
  /// Returns the String path where the file was saved.
  static Future<String> downloadFile(String messageId, String fileName) async {
    try {
      // 1. Get the Correct Download Directory
      final Directory? dir = await _getDownloadDirectory();
      if (dir == null) throw Exception("Could not resolve save directory");

      // 2. Handle Duplicate Filenames (e.g. image.png -> image_1.png)
      String savePath = "${dir.path}${Platform.pathSeparator}$fileName";
      savePath = _getUniquePath(savePath);

      // 3. Download
      final String downloadUrl = "${Env.backendBaseUrl}/api/file/$messageId";

      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            // Optional: Print progress
          }
        },
      );

      print("✅ File saved to: $savePath");
      return savePath; // 👈 RETURN THE PATH

    } catch (e) {
      print("❌ Download Failed: $e");
      throw Exception("Download failed: $e");
    }
  }

  /// 📂 CROSS-PLATFORM DIRECTORY LOGIC
  static Future<Directory?> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Use the standard Download directory
      return Directory('/storage/emulated/0/Download');
    }
    
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return await getDownloadsDirectory();
    }
    
    return await getApplicationDocumentsDirectory(); // iOS
  }

  /// 🔄 DUPLICATE FILE HANDLER (Fixed Syntax)
  static String _getUniquePath(String filePath) {
    File file = File(filePath);
    if (!file.existsSync()) return filePath; // If doesn't exist, return original

    int count = 1;
    String newPath = filePath;
    
    final String dir = file.parent.path;
    final String name = file.uri.pathSegments.last;
    final String ext = name.contains('.') ? ".${name.split('.').last}" : "";
    final String rawName = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;

    while (file.existsSync()) {
      // ✅ Fixed string interpolation here
      newPath = "$dir${Platform.pathSeparator}${rawName}_$count$ext";
      file = File(newPath);
      count++;
    }
    return newPath;
  }
}