import 'dart:collection';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Global LRU thumbnail cache — survives page navigation.
///
/// Stores up to [maxSize] decoded thumbnail bytes, keyed by file-id.
/// Also stores the in-flight [Future] so concurrent callers share one request.
class ThumbnailCacheService {
  ThumbnailCacheService._();
  static final ThumbnailCacheService instance = ThumbnailCacheService._();

  static const int maxSize = 200;

  // LinkedHashMap preserves insertion order → easy LRU eviction from front.
  final LinkedHashMap<dynamic, Future<Uint8List?>> _cache =
      LinkedHashMap<dynamic, Future<Uint8List?>>();

  Future<File> _getThumbFile(dynamic key) async {
    final dir = await getTemporaryDirectory();
    final thumbDir = Directory('${dir.path}/thumbnails');
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }
    return File('${thumbDir.path}/thumb_$key');
  }

  /// Returns the cached (or in-flight) future for [key].
  /// If absent, calls [loader] to produce the future, stores it, and returns it.
  Future<Uint8List?> get(dynamic key, Future<Uint8List?> Function() loader) {
    if (_cache.containsKey(key)) {
      // Move to end (most-recently-used) by re-inserting
      final future = _cache.remove(key)!;
      _cache[key] = future;
      return future;
    }

    // Evict oldest entry if at capacity
    if (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }

    final future = _loadWithDiskCache(key, loader);
    _cache[key] = future;
    return future;
  }

  Future<Uint8List?> _loadWithDiskCache(dynamic key, Future<Uint8List?> Function() loader) async {
    try {
      final file = await _getThumbFile(key);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      
      final bytes = await loader();
      if (bytes != null) {
        file.writeAsBytes(bytes).catchError((e) {
          debugPrint("Failed to save thumbnail to disk: $e");
          return file; // dummy return for catchError typing
        });
      }
      return bytes;
    } catch (e) {
      debugPrint("Thumbnail caching error: $e");
      return await loader();
    }
  }

  /// Remove a single entry (e.g. after a file is deleted).
  void evict(dynamic key) async {
    _cache.remove(key);
    try {
      final file = await _getThumbFile(key);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// Clear everything (e.g. on logout).
  void clear() async {
    _cache.clear();
    try {
      final dir = await getTemporaryDirectory();
      final thumbDir = Directory('${dir.path}/thumbnails');
      if (await thumbDir.exists()) {
        await thumbDir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
