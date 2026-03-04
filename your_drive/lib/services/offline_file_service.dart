import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages offline file storage — saving, removing, checking, and listing
/// files that the user has marked for offline access.
class OfflineFileService {
  static const _offlineIdsKey = 'offline_file_ids';
  static const _cachedListKey = 'cached_file_list';
  static const _offlineDir = 'offline_files';

  // ── Singleton ──────────────────────────────────────────────────────────
  static final OfflineFileService instance = OfflineFileService._();
  OfflineFileService._();

  // ── Offline directory ──────────────────────────────────────────────────
  Future<Directory> _offlineDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/$_offlineDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Save a decrypted file to permanent offline storage ─────────────────
  Future<void> saveToOffline({
    required String fileId,
    required String fileName,
    required File decryptedFile,
  }) async {
    final dir = await _offlineDirectory();
    final target = File('${dir.path}/${fileId}_$fileName');
    await decryptedFile.copy(target.path);

    // Register the ID
    final prefs = await SharedPreferences.getInstance();
    final ids = _getOfflineIds(prefs);
    ids.add(fileId);
    await prefs.setStringList(_offlineIdsKey, ids.toList());
    debugPrint('[Offline] Saved: $fileName');
  }

  // ── Save thumbnail bytes for offline display ───────────────────────────
  Future<void> saveThumbnailOffline(String fileId, Uint8List bytes) async {
    final dir = await _offlineDirectory();
    final target = File('${dir.path}/thumb_$fileId');
    await target.writeAsBytes(bytes);
    debugPrint('[Offline] Thumbnail saved for: $fileId');
  }

  // ── Get offline thumbnail bytes ────────────────────────────────────────
  Future<Uint8List?> getOfflineThumbnail(String fileId) async {
    final dir = await _offlineDirectory();
    final target = File('${dir.path}/thumb_$fileId');
    if (await target.exists()) return target.readAsBytes();
    return null;
  }

  // ── Remove a file from offline storage ─────────────────────────────────
  Future<void> removeFromOffline(String fileId, String fileName) async {
    final dir = await _offlineDirectory();
    final target = File('${dir.path}/${fileId}_$fileName');
    if (await target.exists()) await target.delete();
    // Also remove thumbnail
    final thumb = File('${dir.path}/thumb_$fileId');
    if (await thumb.exists()) await thumb.delete();

    final prefs = await SharedPreferences.getInstance();
    final ids = _getOfflineIds(prefs);
    ids.remove(fileId);
    await prefs.setStringList(_offlineIdsKey, ids.toList());
    debugPrint('[Offline] Removed: $fileName');
  }

  // ── Check if a file is available offline ───────────────────────────────
  Future<bool> isAvailableOffline(String fileId) async {
    final prefs = await SharedPreferences.getInstance();
    return _getOfflineIds(prefs).contains(fileId);
  }

  // ── Get the local File object (or null) ────────────────────────────────
  Future<File?> getOfflineFile(String fileId, String fileName) async {
    final dir = await _offlineDirectory();
    final target = File('${dir.path}/${fileId}_$fileName');
    if (await target.exists()) return target;
    return null;
  }

  // ── Get all offline file IDs ───────────────────────────────────────────
  Future<Set<String>> getOfflineFileIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _getOfflineIds(prefs);
  }

  // ── Cache file list (merges by ID so all type pages stay cached) ───────
  Future<void> cacheFileList(List<Map<String, dynamic>> files) async {
    final prefs = await SharedPreferences.getInstance();

    // Merge into existing cache so caching the 'image' page
    // doesn't wipe out cached 'video' entries
    final existing = prefs.getString(_cachedListKey);
    final Map<String, Map<String, dynamic>> merged = {};

    if (existing != null) {
      try {
        for (final e in jsonDecode(existing) as List) {
          final m = Map<String, dynamic>.from(e as Map);
          merged[m['id'] as String] = m;
        }
      } catch (_) {}
    }

    for (final f in files) {
      merged[f['id'] as String] = f;
    }

    await prefs.setString(_cachedListKey, jsonEncode(merged.values.toList()));
  }

  // ── Retrieve cached file list ──────────────────────────────────────────
  Future<List<Map<String, dynamic>>?> getCachedFileList() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedListKey);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  // ── Helper ─────────────────────────────────────────────────────────────
  Set<String> _getOfflineIds(SharedPreferences prefs) {
    return (prefs.getStringList(_offlineIdsKey) ?? []).toSet();
  }
}
