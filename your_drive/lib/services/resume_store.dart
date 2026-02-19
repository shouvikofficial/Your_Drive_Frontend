import 'package:hive_flutter/hive_flutter.dart';

class ResumeStore {
  static const String _boxName = "uploads";

  static Box get _box => Hive.box(_boxName);

  static Future<void> saveProgress(String id, int chunk) async {
    await _box.put(id, chunk);
  }

  static int getProgress(String id) {
    return _box.get(id, defaultValue: 0);
  }

  static Future<void> clear(String id) async {
    await _box.delete(id);
  }
}
