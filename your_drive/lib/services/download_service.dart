import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/env.dart';

class DownloadService {
  static Future<void> downloadFile(String fileId, String fileName) async {
    // 1️⃣ Ask backend for REAL Telegram URL
    final res = await http.get(
      Uri.parse("${Env.backendBaseUrl}/download/$fileId"),
    );

    if (res.statusCode != 200) {
      throw Exception("Failed to get download URL");
    }

    final decoded = jsonDecode(res.body);
    final String url = decoded['url'];

    // 2️⃣ Download file bytes
    final fileRes = await http.get(Uri.parse(url));

    if (fileRes.statusCode != 200) {
      throw Exception("Failed to download file");
    }

    // 3️⃣ Save to Downloads folder (Windows / Desktop safe)
    final dir = await getDownloadsDirectory();
    if (dir == null) throw Exception("Downloads directory not found");

    final file = File("${dir.path}/$fileName");
    await file.writeAsBytes(fileRes.bodyBytes);
  }
}
