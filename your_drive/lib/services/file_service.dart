import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

class FileService {
  final Dio _dio = Dio();

  /// 🗑 DELETE FILE
  /// Defining the parameters to match your UI's call
  Future<void> deleteFile({
    required int messageId,
    required String supabaseId,
    required Function(String) onSuccess,
    required Function(String) onError,
  }) async {
    try {
      // 1. Delete physically from Telegram via backend
      final res = await _dio.delete("${Env.backendBaseUrl}/api/delete/$messageId");

      if (res.statusCode == 200) {
        // 2. Delete metadata from Supabase database
        await Supabase.instance.client.from('files').delete().eq('id', supabaseId);
        onSuccess("Deleted successfully");
      } else {
        onError("Delete failed");
      }
    } catch (e) {
      onError("Delete failed: ${e.toString()}");
    }
  }
}