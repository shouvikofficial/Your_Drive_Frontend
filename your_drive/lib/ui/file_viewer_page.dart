import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../config/env.dart';
import '../services/vault_service.dart';
import '../services/file_service.dart';
import '../services/download_service.dart';
import '../services/preview_cache_service.dart';
import '../services/thumbnail_cache_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FileViewerPage — Google-Drive-style viewer with swipe navigation
// ─────────────────────────────────────────────────────────────────────────────

class FileViewerPage extends StatefulWidget {
  /// All files the user can swipe through.
  final List<Map<String, dynamic>> files;

  /// Which file to open first.
  final int initialIndex;

  const FileViewerPage({
    super.key,
    required this.files,
    required this.initialIndex,
  });

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentFile => widget.files[_currentIndex];

  // ── Share (cache-aware: no re-decrypt if already cached) ──────────────────
  Future<void> _shareFile(Map<String, dynamic> file) async {
    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preparing file for sharing…"), duration: Duration(days: 1)),
      );

      final dir = await getTemporaryDirectory();
      final cacheFile = File("${dir.path}/msg_${file['message_id']}_${file['name']}");

      File decryptedFile;
      if (cacheFile.existsSync()) {
        // Already decrypted — reuse cache, no download needed
        decryptedFile = cacheFile;
      } else {
        final supabase = Supabase.instance.client;
        final fileData = await supabase
            .from('files')
            .select('iv, chunk_size, total_chunks')
            .eq('message_id', file['message_id'])
            .maybeSingle();

        if (fileData == null) throw Exception("Metadata missing");

        final response = await http.get(
          Uri.parse("${Env.backendBaseUrl}/api/file/${file['message_id']}"),
        );
        if (response.statusCode != 200) throw Exception("Download failed");

        decryptedFile = await _decryptFullFile(
          response.bodyBytes,
          fileData['iv'] as String,
          fileData['chunk_size'] as int,
          fileData['total_chunks'] as int,
          cacheFile,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Share.shareXFiles([XFile(decryptedFile.path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Share failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _deleteFile(Map<String, dynamic> file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete file?"),
        content: Text('"${file['name']}" will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Evict preview cache for this file
      PreviewCacheService.instance.evict(file['message_id'].toString());
      ThumbnailCacheService.instance.evict(file['id']);

      await FileService().deleteFile(
        messageId: file['message_id'],
        supabaseId: file['id'],
        onSuccess: (_) {
          if (mounted) Navigator.pop(context, true); // signal refresh to parent
        },
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e), backgroundColor: Colors.red),
            );
          }
        },
      );
    }
  }

  // ── Decrypt helper ────────────────────────────────────────────────────────
  Future<File> _decryptFullFile(
    List<int> encryptedBytes,
    String ivBase64,
    int chunkSize,
    int totalChunks,
    File targetFile,
  ) async {
    final baseNonce = base64Decode(ivBase64);
    final secretKey = await VaultService().getSecretKey();
    final algorithm = AesGcm.with256bits();
    final output = BytesBuilder();
    int offset = 0;

    for (int i = 0; i < totalChunks; i++) {
      final int end = (i == totalChunks - 1)
          ? encryptedBytes.length
          : offset + chunkSize + 16;
      final chunk = encryptedBytes.sublist(offset, end);
      final macBytes = chunk.sublist(chunk.length - 16);
      final cipherText = chunk.sublist(0, chunk.length - 16);

      final nonce = Uint8List.fromList(baseNonce);
      nonce[8] = (i >> 24) & 0xFF;
      nonce[9] = (i >> 16) & 0xFF;
      nonce[10] = (i >> 8) & 0xFF;
      nonce[11] = i & 0xFF;

      final decrypted = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );
      output.add(decrypted);
      offset = end;
    }

    await targetFile.writeAsBytes(output.toBytes());
    return targetFile;
  }

  // ── 3-dot menu ────────────────────────────────────────────────────────────
  void _showFileMenu(BuildContext context, Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => _FileInfoSheet(
        file: file,
        onShare: () { Navigator.pop(context); _shareFile(file); },
        onDownload: () {
          Navigator.pop(context);
          DownloadService.downloadFile(file['message_id'].toString(), file['name']);
        },
        onDelete: () { Navigator.pop(context); _deleteFile(file); },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.files.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.55),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currentFile['name'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (hasMultiple)
              Text(
                '${_currentIndex + 1} of ${widget.files.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showFileMenu(context, _currentFile),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        itemCount: widget.files.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return AnimatedBuilder(
            animation: _pageController,
            child: _SingleFileViewer(
              key: ValueKey(widget.files[index]['message_id']),
              file: widget.files[index],
            ),
            builder: (context, child) {
              double offset = 0.0;
              if (_pageController.position.haveDimensions) {
                offset = (index - (_pageController.page ?? index.toDouble()))
                    .clamp(-1.0, 1.0);
              }
              final scale   = 1.0 - 0.06 * offset.abs();
              final opacity = 1.0 - 0.35 * offset.abs();
              return Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SingleFileViewer — one page inside the PageView
// ─────────────────────────────────────────────────────────────────────────────

class _SingleFileViewer extends StatefulWidget {
  final Map<String, dynamic> file;
  const _SingleFileViewer({super.key, required this.file});

  @override
  State<_SingleFileViewer> createState() => _SingleFileViewerState();
}

class _SingleFileViewerState extends State<_SingleFileViewer>
    with AutomaticKeepAliveClientMixin {
  bool _isLoading = true;
  String _loadingStatus = 'Fetching metadata…';
  String? _error;
  Uint8List? _imageBytes;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _tempFile;

  /// Keep this page alive when swiped off-screen (Google Drive behaviour).
  @override
  bool get wantKeepAlive => true;

  String get _messageId => widget.file['message_id'].toString();
  String get _fileName => widget.file['name'] as String;

  final _previewCache = PreviewCacheService.instance;

  @override
  void initState() {
    super.initState();
    _loadFromCacheOrDownload();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  // ─── Load from in-memory cache first, then disk, then network ───────────
  Future<void> _loadFromCacheOrDownload() async {
    try {
      // ① Check in-memory image cache (instant — no I/O)
      if (_isImage(_fileName)) {
        final cached = _previewCache.getImage(_messageId);
        if (cached != null) {
          if (mounted) setState(() { _imageBytes = cached; _isLoading = false; });
          return;
        }
      }

      // ② Check in-memory file cache (video / document)
      final cachedFile = _previewCache.getFile(_messageId);
      if (cachedFile != null) {
        if (mounted) setState(() => _loadingStatus = 'Opening from cache…');
        await _openFile(cachedFile);
        return;
      }

      // ③ Fall through to disk cache / network
      await _downloadAndDecrypt();
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _isLoading = false; });
      }
    }
  }

  // ─── Download + decrypt (with disk cache) ────────────────────────────────
  Future<void> _downloadAndDecrypt() async {
    try {
      final dir = await getTemporaryDirectory();
      final cacheFile = File("${dir.path}/msg_${_messageId}_$_fileName");

      if (cacheFile.existsSync()) {
        if (mounted) setState(() => _loadingStatus = 'Opening from cache…');
        await _openFile(cacheFile);
        return;
      }

      // Fetch metadata
      final supabase = Supabase.instance.client;
      final fileData = await supabase
          .from('files')
          .select('iv, chunk_size, total_chunks')
          .eq('message_id', _messageId)
          .maybeSingle();

      if (fileData == null) throw Exception("Metadata missing");

      final ivBase64 = fileData['iv'] as String?;
      final int chunkSize = fileData['chunk_size'] as int;
      final int totalChunks = fileData['total_chunks'] as int;
      if (ivBase64 == null) throw Exception("Missing IV");

      // Download
      if (mounted) setState(() => _loadingStatus = 'Downloading…');
      final response = await http.get(
        Uri.parse("${Env.backendBaseUrl}/api/file/$_messageId"),
      );
      if (response.statusCode != 200) throw Exception("Download failed");

      // Decrypt
      if (mounted) setState(() => _loadingStatus = 'Decrypting your data…');
      final decryptedFile = await _decryptFullFile(
        response.bodyBytes,
        ivBase64,
        chunkSize,
        totalChunks,
        cacheFile,
      );

      if (!mounted) return;
      await _openFile(decryptedFile);
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _isLoading = false; });
      }
    }
  }

  Future<void> _openFile(File file) async {
    if (_isImage(_fileName)) {
      final bytes = await file.readAsBytes();
      // Store in memory cache for instant re-access
      _previewCache.putImage(_messageId, bytes);
      _previewCache.putFile(_messageId, file);
      if (mounted) setState(() { _imageBytes = bytes; _isLoading = false; });
    } else if (_isVideo(_fileName)) {
      if (mounted) setState(() => _loadingStatus = 'Preparing player…');
      _tempFile = file;
      _previewCache.putFile(_messageId, file);
      await _initializeVideo();
    } else {
      if (mounted) setState(() => _loadingStatus = 'Opening file…');
      _tempFile = file;
      _previewCache.putFile(_messageId, file);
      await OpenFilex.open(file.path);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<File> _decryptFullFile(
    List<int> encryptedBytes,
    String ivBase64,
    int chunkSize,
    int totalChunks,
    File targetFile,
  ) async {
    final baseNonce = base64Decode(ivBase64);
    final secretKey = await VaultService().getSecretKey();
    final algorithm = AesGcm.with256bits();
    final output = BytesBuilder();
    int offset = 0;

    for (int i = 0; i < totalChunks; i++) {
      final int end = (i == totalChunks - 1)
          ? encryptedBytes.length
          : offset + chunkSize + 16;
      final chunk = encryptedBytes.sublist(offset, end);
      final macBytes = chunk.sublist(chunk.length - 16);
      final cipherText = chunk.sublist(0, chunk.length - 16);

      final nonce = Uint8List.fromList(baseNonce);
      nonce[8] = (i >> 24) & 0xFF;
      nonce[9] = (i >> 16) & 0xFF;
      nonce[10] = (i >> 8) & 0xFF;
      nonce[11] = i & 0xFF;

      final decrypted = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );
      output.add(decrypted);
      offset = end;
    }

    await targetFile.writeAsBytes(output.toBytes());
    return targetFile;
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController = VideoPlayerController.file(_tempFile!);
      await _videoController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoController!.value.aspectRatio,
      );
      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() { _error = "Failed to load video"; _isLoading = false; });
    }
  }

  bool _isImage(String name) =>
      RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|heic)$', caseSensitive: false).hasMatch(name);

  bool _isVideo(String name) =>
      RegExp(r'\.(mp4|mov|avi|mkv|webm)$', caseSensitive: false).hasMatch(name);

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    if (_isLoading) {
      return Center(child: _DecryptingIndicator(status: _loadingStatus));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (_chewieController != null) return Chewie(controller: _chewieController!);
    if (_imageBytes != null) {
      return PhotoView(
        imageProvider: MemoryImage(_imageBytes!),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      );
    }
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FileInfoSheet — bottom sheet from 3-dot menu (dark theme for viewer)
// ─────────────────────────────────────────────────────────────────────────────

class _FileInfoSheet extends StatelessWidget {
  final Map<String, dynamic> file;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _FileInfoSheet({
    required this.file,
    required this.onShare,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = file['name'] ?? '-';
    final type = (file['type'] ?? '-').toString().toUpperCase();
    final size = _formatSize(file['size']);
    final date = _formatDate(file['created_at']);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 38, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // File name row
            Row(
              children: [
                Icon(Icons.insert_drive_file_outlined, color: Colors.grey[500], size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Info rows
            _DarkInfoRow(icon: Icons.category_outlined,  label: 'Type',     value: type),
            _DarkInfoRow(icon: Icons.storage_outlined,   label: 'Size',     value: size),
            _DarkInfoRow(icon: Icons.schedule_outlined,  label: 'Uploaded', value: date),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),

            // Action tiles
            _ActionTile(icon: Icons.share_outlined,    label: 'Share',    color: Colors.black87,    onTap: onShare),
            _ActionTile(icon: Icons.download_outlined, label: 'Download', color: Colors.black87,    onTap: onDownload),
            _ActionTile(icon: Icons.delete_outline,    label: 'Delete',   color: Colors.red,        onTap: onDelete),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  static String _formatSize(dynamic bytes) {
    if (bytes == null) return '-';
    final int b = bytes is int ? bytes : int.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatDate(dynamic isoDate) {
    if (isoDate == null) return '-';
    try {
      final dt = DateTime.parse(isoDate.toString()).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final period = dt.hour < 12 ? 'AM' : 'PM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ·  $hour:$min $period';
    } catch (_) { return '-'; }
  }
}

class _DarkInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DarkInfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 17, color: Colors.grey[500]),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DecryptingIndicator
// ─────────────────────────────────────────────────────────────────────────────

class _DecryptingIndicator extends StatelessWidget {
  final String status;
  const _DecryptingIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 42,
          height: 42,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, color: Colors.white54, size: 15),
            const SizedBox(width: 7),
            Text(
              status,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
