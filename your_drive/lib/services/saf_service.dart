import 'dart:typed_data';
import 'package:flutter/services.dart';

class SafService {
  static const _channel = MethodChannel('saf_upload_channel');

  /// 📂 Pick MULTIPLE files using Android SAF
  static Future<List<Map<String, dynamic>>?> pickFiles() async {
    final result = await _channel.invokeMethod('pickFilesSaf');

    if (result == null) return null;

    // Convert dynamic list → typed list
    return List<Map<String, dynamic>>.from(
      result.map((e) => Map<String, dynamic>.from(e)),
    );
  }

  /// 📦 Read chunk from SAF stream
  static Future<List<int>?> readChunk({
    required String uri,
    required int offset,
    required int length,
  }) async {
    final result = await _channel.invokeMethod(
      'readSafChunk',
      {
        "uri": uri,
        "offset": offset,
        "length": length,
      },
    );

    if (result == null) return null;
    return List<int>.from(result);
  }

  /// 🎬 Get video thumbnail natively from SAF content URI
  /// Uses Android's MediaMetadataRetriever — works with content:// URIs
  /// without needing to copy the entire file.
  static Future<Uint8List?> getVideoThumbnail(String uri) async {
    try {
      final result = await _channel.invokeMethod(
        'getSafVideoThumbnail',
        {"uri": uri},
      );
      if (result == null) return null;
      return Uint8List.fromList(List<int>.from(result));
    } catch (e) {
      return null;
    }
  }
}
