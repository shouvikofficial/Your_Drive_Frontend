import 'package:flutter/services.dart';
import 'dart:typed_data';

class SafBridge {
  static const _channel = MethodChannel('saf_bridge');

  /// Pick MULTIPLE files
  static Future<List<String>> pickFiles() async {
    final result = await _channel.invokeMethod<List>('pickFiles');
    return List<String>.from(result ?? []);
  }

  /// Get name & size
  static Future<Map<String, dynamic>> getFileInfo(String uri) async {
    final result = await _channel.invokeMethod('getFileInfo', {'uri': uri});
    return Map<String, dynamic>.from(result);
  }

  /// ⭐ Read file bytes from SAF URI
  static Future<Uint8List> readFileBytes(String uri) async {
    final result = await _channel.invokeMethod('readFileBytes', {'uri': uri});
    return Uint8List.fromList(List<int>.from(result));
  }
}