import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

class FileService {
  static Future<void> deleteFile({
    required int messageId,
    required String rowId,
  }) async {
    // 1️⃣ Delete from Telegram
    final res = await http.delete(
      Uri.parse("${Env.backendBaseUrl}/delete/$messageId"),
    );

    if (res.statusCode != 200) {
      throw Exception("Telegram delete failed");
    }

    // 2️⃣ Delete from Supabase
    await Supabase.instance.client
        .from('files')
        .delete()
        .eq('id', rowId);
  }
}
