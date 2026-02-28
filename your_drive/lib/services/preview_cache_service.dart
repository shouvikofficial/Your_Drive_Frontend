import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

/// In-memory LRU cache for file previews — Google-Drive-style.
///
/// Keeps decoded image bytes and decrypted file paths alive across
/// page navigations so swiping back to a previously viewed file is instant.
///
/// Two separate caches:
///   • [_imageCache]  – decoded JPEG/PNG bytes (for PhotoView)
///   • [_fileCache]   – decrypted [File] on disk  (for videos / documents)
///
/// Both are small LRU maps.  Images are evicted by count; files are just
/// path references (the actual bytes live in the temp directory).
class PreviewCacheService {
  PreviewCacheService._();
  static final PreviewCacheService instance = PreviewCacheService._();

  /// Max number of image byte-arrays kept in RAM.
  static const int _maxImages = 15;

  /// Max number of file path entries tracked.
  static const int _maxFiles = 30;

  // ── Image bytes cache ───────────────────────────────────────────────────
  final LinkedHashMap<String, Uint8List> _imageCache =
      LinkedHashMap<String, Uint8List>();

  /// Store decoded image bytes, keyed by message_id.
  void putImage(String messageId, Uint8List bytes) {
    // Move to end (most-recently-used)
    _imageCache.remove(messageId);
    if (_imageCache.length >= _maxImages) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[messageId] = bytes;
  }

  /// Get cached image bytes, or null.
  Uint8List? getImage(String messageId) {
    final bytes = _imageCache.remove(messageId);
    if (bytes == null) return null;
    // Re-insert at end (most-recently-used)
    _imageCache[messageId] = bytes;
    return bytes;
  }

  // ── Decrypted file cache ────────────────────────────────────────────────
  final LinkedHashMap<String, File> _fileCache =
      LinkedHashMap<String, File>();

  /// Remember that a decrypted file exists at [file] for [messageId].
  void putFile(String messageId, File file) {
    _fileCache.remove(messageId);
    if (_fileCache.length >= _maxFiles) {
      _fileCache.remove(_fileCache.keys.first);
    }
    _fileCache[messageId] = file;
  }

  /// Get the cached decrypted file (only if it still exists on disk).
  File? getFile(String messageId) {
    final file = _fileCache[messageId];
    if (file == null) return null;
    if (!file.existsSync()) {
      _fileCache.remove(messageId);
      return null;
    }
    // Move to end (most-recently-used)
    _fileCache.remove(messageId);
    _fileCache[messageId] = file;
    return file;
  }

  // ── Housekeeping ────────────────────────────────────────────────────────

  /// Evict all caches for a specific file (e.g. after delete).
  void evict(String messageId) {
    _imageCache.remove(messageId);
    _fileCache.remove(messageId);
  }

  /// Clear everything (e.g. on logout).
  void clear() {
    _imageCache.clear();
    _fileCache.clear();
  }
}
