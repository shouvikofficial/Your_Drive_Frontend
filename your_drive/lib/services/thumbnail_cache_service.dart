import 'dart:collection';
import 'dart:typed_data';

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

    final future = loader();
    _cache[key] = future;
    return future;
  }

  /// Remove a single entry (e.g. after a file is deleted).
  void evict(dynamic key) => _cache.remove(key);

  /// Clear everything (e.g. on logout).
  void clear() => _cache.clear();
}
