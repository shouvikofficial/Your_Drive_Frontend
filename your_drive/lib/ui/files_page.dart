import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../theme/app_colors.dart';
import '../config/env.dart';
import '../services/file_service.dart';
import '../services/download_service.dart';
import '../services/vault_service.dart';
import '../services/thumbnail_cache_service.dart';
import '../services/offline_file_service.dart';
import 'upload_page.dart';
import 'file_viewer_page.dart';

class FilesPage extends StatefulWidget {
  final String type;
  final String? folderId;

  const FilesPage({
    super.key,
    required this.type,
    this.folderId,
  });

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  bool isGridView = true;
  String? _loadError;

  final Set<Map<String, dynamic>> selectedFiles = {};
  bool isSelectionMode = false;

  /// IDs of files the user has marked for offline access.
  Set<String> _offlineIds = {};

  /// Scoped ScaffoldMessenger — all snackbars die with this page.
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  void _showSnack(SnackBar snackBar) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }

  void _hideSnack() {
    _messengerKey.currentState?.hideCurrentSnackBar();
  }

  Future<Uint8List?> _getCachedThumbnail(Map<String, dynamic> file) {
    return ThumbnailCacheService.instance.get(
      file['id'],
      () async {
        // For offline-pinned files, try local sources first
        if (_offlineIds.contains(file['id'])) {
          // 1) Saved thumbnail
          final offlineThumb = await OfflineFileService.instance
              .getOfflineThumbnail(file['id']);
          if (offlineThumb != null) return offlineThumb;

          // 2) For images, use the offline file itself as thumbnail
          final name = file['name'] as String? ?? '';
          if (RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|heic)$', caseSensitive: false).hasMatch(name)) {
            final offlineFile = await OfflineFileService.instance
                .getOfflineFile(file['id'], name);
            if (offlineFile != null) return offlineFile.readAsBytes();
          }
        }
        return _getThumbnail(file);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchFilesInitial();
  }

  Future<void> _fetchFilesInitial() async {
    setState(() { _isLoading = true; _loadError = null; });
    await _loadData();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshFiles() async {
    await _loadData();
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    final offlineSvc = OfflineFileService.instance;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity.every((r) => r == ConnectivityResult.none);

      if (isOffline) {
        // ── No internet: load from cache, show only offline files ──
        final cached = await offlineSvc.getCachedFileList();
        final ids = await offlineSvc.getOfflineFileIds();
        _offlineIds = ids;
        if (cached != null) {
          var filtered = cached.where((f) => ids.contains(f['id']));
          // Apply the same type/folder filter as the online query
          if (widget.type != 'all') {
            filtered = filtered.where((f) => f['type'] == widget.type);
          } else if (widget.folderId != null) {
            filtered = filtered.where((f) => f['folder_id'] == widget.folderId);
          }
          _files = filtered.toList();
        } else {
          _files = [];
        }
        selectedFiles.clear();
        isSelectionMode = false;
        return;
      }

      // ── Online: fetch from Supabase ──
      final supabase = Supabase.instance.client;
      var query = supabase.from('files').select();

      if (widget.type != 'all') {
        query = query.eq('type', widget.type);
      } else if (widget.folderId != null) {
        query = query.eq('folder_id', widget.folderId!);
      }

      final response = await query.order('created_at', ascending: false);
      _files = List<Map<String, dynamic>>.from(response);
      selectedFiles.clear();
      isSelectionMode = false;

      // Cache list & refresh offline IDs
      await offlineSvc.cacheFileList(_files);
      _offlineIds = await offlineSvc.getOfflineFileIds();
    } catch (e) {
      debugPrint("Error loading files: $e");
      // Attempt cached fallback on any network error
      final cached = await offlineSvc.getCachedFileList();
      final ids = await offlineSvc.getOfflineFileIds();
      _offlineIds = ids;
      if (cached != null && _files.isEmpty) {
        var filtered = cached.where((f) => ids.contains(f['id']));
        if (widget.type != 'all') {
          filtered = filtered.where((f) => f['type'] == widget.type);
        } else if (widget.folderId != null) {
          filtered = filtered.where((f) => f['folder_id'] == widget.folderId);
        }
        _files = filtered.toList();
        if (_files.isEmpty) _loadError = e.toString();
      } else {
        _loadError = e.toString();
      }
    }
  }

  // --- Selection Logic ---

  void _toggleSelection(Map<String, dynamic> file) {
    setState(() {
      if (selectedFiles.contains(file)) {
        selectedFiles.remove(file);
        if (selectedFiles.isEmpty) isSelectionMode = false;
      } else {
        selectedFiles.add(file);
        isSelectionMode = true;
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (selectedFiles.length == _files.length) {
        selectedFiles.clear();
        isSelectionMode = false;
      } else {
        selectedFiles.addAll(_files);
        isSelectionMode = true;
      }
    });
  }

  // --- Bulk Actions ---

  // --- Rename Logic ---

  String _resolveUniqueName(String desiredName, String excludeId) {
    final existing = _files
        .where((f) => f['id'] != excludeId)
        .map((f) => f['name'] as String)
        .toSet();

    if (!existing.contains(desiredName)) return desiredName;

    // Split name and extension
    final dotIndex = desiredName.lastIndexOf('.');
    final String baseName;
    final String ext;
    if (dotIndex != -1 && dotIndex != 0) {
      baseName = desiredName.substring(0, dotIndex);
      ext = desiredName.substring(dotIndex); // includes the dot
    } else {
      baseName = desiredName;
      ext = '';
    }

    int counter = 1;
    String candidate;
    do {
      candidate = '$baseName ($counter)$ext';
      counter++;
    } while (existing.contains(candidate));

    return candidate;
  }

  Future<void> _renameFile(Map<String, dynamic> file) async {
    final String fullName = file['name'] ?? '';

    // Split into name + extension (like Google Drive)
    final dotIndex = fullName.lastIndexOf('.');
    final String nameOnly;
    final String extension; // includes the dot, e.g. ".jpg"
    if (dotIndex > 0) {
      nameOnly = fullName.substring(0, dotIndex);
      extension = fullName.substring(dotIndex);
    } else {
      nameOnly = fullName;
      extension = '';
    }

    final controller = TextEditingController(text: nameOnly);
    // Select all text so user can type immediately
    controller.selection = TextSelection(baseOffset: 0, extentOffset: nameOnly.length);

    final newBaseName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'File name',
            // Show extension as a non-editable suffix
            suffixText: extension.isNotEmpty ? extension : null,
            suffixStyle: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newBaseName == null || newBaseName.isEmpty) return;

    // Re-append original extension automatically
    final newName = '$newBaseName$extension';

    if (newName == fullName) return; // No change

    final resolvedName = _resolveUniqueName(newName, file['id'] as String);

    try {
      await Supabase.instance.client
          .from('files')
          .update({'name': resolvedName})
          .eq('id', file['id']);

      if (resolvedName != newName && mounted) {
        _showSnack(
          SnackBar(
            content: Text('Saved as "$resolvedName" to avoid duplicates.'),
          ),
        );
      }

      await _loadData();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        _showSnack(
          SnackBar(content: Text('Rename failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  Future<void> _bulkRemoveOffline() async {
    final files = selectedFiles.where((f) => _offlineIds.contains(f['id'])).toList();
    setState(() { selectedFiles.clear(); isSelectionMode = false; });
    for (final file in files) {
      _removeOffline(file);
    }
  }

  Future<void> _bulkMakeOffline() async {
    final files = selectedFiles.where((f) => !_offlineIds.contains(f['id'])).toList();
    setState(() { selectedFiles.clear(); isSelectionMode = false; });
    if (files.isEmpty) {
      _showSnack(
        const SnackBar(content: Text('All selected files are already offline')),
      );
      return;
    }
    for (final file in files) {
      _makeOffline(file);
    }
  }

  Future<void> _bulkShare() async {
    final files = selectedFiles.toList();
    setState(() { selectedFiles.clear(); isSelectionMode = false; });

    _showSnack(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text("Preparing ${files.length} files…"),
        ]),
        duration: const Duration(days: 1),
      ),
    );

    try {
      final List<XFile> xFiles = [];
      for (var file in files) {
        // Try offline file first, then temp cache, then download
        final offlineFile = await OfflineFileService.instance
            .getOfflineFile(file['id'], file['name']);
        if (offlineFile != null) {
          xFiles.add(XFile(offlineFile.path));
          continue;
        }

        final dir = await getTemporaryDirectory();
        final cacheFile = File("${dir.path}/msg_${file['message_id']}_${file['name']}");
        if (cacheFile.existsSync()) {
          xFiles.add(XFile(cacheFile.path));
          continue;
        }

        // Download + decrypt
        final supabase = Supabase.instance.client;
        final fileData = await supabase
            .from('files')
            .select('iv, chunk_size, total_chunks')
            .eq('message_id', file['message_id'])
            .maybeSingle();
        if (fileData == null) continue;

        final url = "${Env.backendBaseUrl}/api/file/${file['message_id']}";
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) continue;

        final decryptedFile = await _decryptFullFile(
          response.bodyBytes,
          fileData['iv'],
          fileData['chunk_size'],
          fileData['total_chunks'],
          cacheFile,
        );
        xFiles.add(XFile(decryptedFile.path));
      }

      if (!mounted) return;
      _hideSnack();

      if (xFiles.isEmpty) {
        _showSnack(
          const SnackBar(content: Text('No files to share'), backgroundColor: Colors.orange),
        );
        return;
      }

      await Share.shareXFiles(xFiles);
    } catch (e) {
      if (!mounted) return;
      _hideSnack();
      _showSnack(
        SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _bulkDelete() async {
    final count = selectedFiles.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete $count items?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      _showSnack(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 15),
              Text("Deleting files..."),
            ],
          ),
          duration: Duration(days: 1),
        ),
      );

      try {
        for (var file in selectedFiles) {
          ThumbnailCacheService.instance.evict(file['id']);
          await FileService().deleteFile(
            messageId: file['message_id'],
            supabaseId: file['id'],
            onSuccess: (_) {},
            onError: (e) {},
          );
        }
      } finally {
        _hideSnack();
        await _loadData();
        if (mounted) setState(() {}); 
      }
    }
  }

  Future<void> _bulkDownload() async {
    final files = selectedFiles.toList();
    setState(() {
      selectedFiles.clear();
      isSelectionMode = false;
    });

    _showSnack(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text("Downloading ${files.length} files..."),
        ]),
        duration: const Duration(days: 1),
      ),
    );

    int success = 0;
    int failed = 0;
    for (var file in files) {
      try {
        await DownloadService.downloadFile(file['message_id'].toString(), file['name']);
        success++;
      } catch (_) {
        failed++;
      }
    }

    if (!mounted) return;
    _hideSnack();
    _showSnack(
      SnackBar(
        content: Text(failed == 0
            ? "$success files downloaded successfully"
            : "$success downloaded, $failed failed"),
        backgroundColor: failed == 0 ? Colors.green : Colors.orange,
      ),
    );
  }

  // --- Offline toggle ---

  /// Files currently being saved for offline — prevents duplicate taps.
  final Set<String> _savingOfflineIds = {};

  void _updateOfflineSnackbar() {
    if (!mounted) return;
    final count = _savingOfflineIds.length;
    if (count == 0) return;
    _hideSnack();
    _showSnack(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text(count == 1
              ? 'Making available offline…'
              : 'Saving $count files offline…'),
        ]),
        duration: const Duration(days: 1),
      ),
    );
  }

  Future<void> _makeOffline(Map<String, dynamic> file) async {
    final fileId = file['id'] as String;

    // Prevent duplicate taps
    if (_savingOfflineIds.contains(fileId) || _offlineIds.contains(fileId)) return;

    _savingOfflineIds.add(fileId);
    _updateOfflineSnackbar();

    try {
      // Reuse cached temp file or download + decrypt
      final dir = await getTemporaryDirectory();
      final cacheFile = File("${dir.path}/msg_${file['message_id']}_${file['name']}");

      File decryptedFile;
      if (cacheFile.existsSync()) {
        decryptedFile = cacheFile;
      } else {
        final supabase = Supabase.instance.client;
        final fileData = await supabase
            .from('files')
            .select('iv, chunk_size, total_chunks')
            .eq('message_id', file['message_id'])
            .maybeSingle();
        if (fileData == null) throw Exception('Metadata missing');

        final url = '${Env.backendBaseUrl}/api/file/${file['message_id']}';
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) throw Exception('Download failed');

        decryptedFile = await _decryptFullFile(
          response.bodyBytes,
          fileData['iv'],
          fileData['chunk_size'],
          fileData['total_chunks'],
          cacheFile,
        );
      }

      await OfflineFileService.instance.saveToOffline(
        fileId: fileId,
        fileName: file['name'],
        decryptedFile: decryptedFile,
      );

      // Also persist the thumbnail for offline display
      try {
        final thumbBytes = await ThumbnailCacheService.instance.get(
          fileId, () => _getThumbnail(file),
        );
        if (thumbBytes != null) {
          await OfflineFileService.instance.saveThumbnailOffline(fileId, thumbBytes);
        }
      } catch (_) {}

      if (!mounted) return;
      _offlineIds.add(fileId);
      _savingOfflineIds.remove(fileId);
      setState(() {});

      // Show final snackbar only when all queued saves finish
      if (_savingOfflineIds.isEmpty) {
        _hideSnack();
        _showSnack(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.offline_pin, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Available offline'),
            ]),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        _updateOfflineSnackbar();
      }
    } catch (e) {
      _savingOfflineIds.remove(fileId);
      if (!mounted) return;
      if (_savingOfflineIds.isEmpty) {
        _hideSnack();
      } else {
        _updateOfflineSnackbar();
      }
      _showSnack(
        SnackBar(content: Text('Offline save failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _removeOffline(Map<String, dynamic> file) async {
    await OfflineFileService.instance.removeFromOffline(file['id'], file['name']);
    if (!mounted) return;
    _offlineIds.remove(file['id']);
    _files.removeWhere((f) => f['id'] == file['id']);
    setState(() {});
    _showSnack(
      const SnackBar(
        content: Text('Removed from offline'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // --- Sharing & Decryption ---

  /// Single file download with user feedback
  Future<void> _downloadSingleFile(Map<String, dynamic> file) async {
    _showSnack(
      SnackBar(
        content: Row(children: [
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text("Downloading ${file['name']}...")),
        ]),
        duration: const Duration(days: 1),
      ),
    );

    try {
      final savePath = await DownloadService.downloadFile(
        file['message_id'].toString(),
        file['name'],
      );

      if (!mounted) return;
      _hideSnack();

      final isGallery = savePath.startsWith("Gallery/");
      final displayName = savePath.split(Platform.pathSeparator).last.split('/').last;

      _showSnack(
        SnackBar(
          content: Row(children: [
            Icon(
              isGallery ? Icons.photo_library_rounded : Icons.download_done_rounded,
              color: Colors.white, size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(
              isGallery ? "Saved to Gallery: $displayName" : "Saved to Downloads: $displayName",
            )),
          ]),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _hideSnack();
      _showSnack(
        SnackBar(
          content: Text("Download failed: ${e.toString().replaceAll('Exception: ', '')}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

 Future<void> _shareFile(Map<String, dynamic> file) async {
  try {
    _showSnack(
      const SnackBar(content: Text("Preparing secure file…"), duration: Duration(days: 1)),
    );

    // ── Cache check: reuse already-decrypted file if available ────────────
    final dir = await getTemporaryDirectory();
    final cacheFile = File("${dir.path}/msg_${file['message_id']}_${file['name']}");

    File decryptedFile;
    if (cacheFile.existsSync()) {
      decryptedFile = cacheFile;
    } else {
      final supabase = Supabase.instance.client;
      final fileData = await supabase
          .from('files')
          .select('iv, chunk_size, total_chunks')
          .eq('message_id', file['message_id'])
          .maybeSingle();

      if (fileData == null) throw Exception("Metadata missing");

      final url = "${Env.backendBaseUrl}/api/file/${file['message_id']}";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) throw Exception("Download failed");

      decryptedFile = await _decryptFullFile(
        response.bodyBytes,
        fileData['iv'],
        fileData['chunk_size'],
        fileData['total_chunks'],
        cacheFile,   // write to same cache path the viewer uses
      );
    }

    if (!mounted) return;
    _hideSnack();

    final box = context.findRenderObject() as RenderBox?;
    await Share.shareXFiles(
      [XFile(decryptedFile.path)],
      sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  } catch (e) {
    if (mounted) {
      _hideSnack();
      _showSnack(
        SnackBar(content: Text("Share failed: $e"), backgroundColor: Colors.red),
      );
    }
  }
}

Future<File> _decryptFullFile(
  List<int> encryptedBytes,
  String ivBase64,
  int chunkSize,
  int totalChunks,
  File targetFile,   // caller provides the destination (shared cache path)
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

Future<Uint8List?> _getThumbnail(Map<String, dynamic> file) async {
  try {
    if (file['thumbnail_id'] == null) return null;

    // thumbnail_iv may already be in the file map from the list query
    final String? thumbIvBase64 =
        file['thumbnail_iv'] as String? ??
        await _fetchThumbnailIv(file['message_id']);

    if (thumbIvBase64 == null) return null;

    final url =
        "${Env.backendBaseUrl}/api/thumbnail/${file['thumbnail_id']}";

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final encryptedBytes = response.bodyBytes;

    final secretKey = await VaultService().getSecretKey();
    final algorithm = AesGcm.with256bits();

    final nonce = base64Decode(thumbIvBase64); // ✅ use thumbnail's own IV

    final macBytes = encryptedBytes.sublist(encryptedBytes.length - 16);
    final cipherText = encryptedBytes.sublist(0, encryptedBytes.length - 16);

    final decrypted = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: secretKey,
    );

    return Uint8List.fromList(decrypted);
  } catch (e) {
    debugPrint("Thumbnail error: $e");
    return null;
  }
}

Future<String?> _fetchThumbnailIv(dynamic messageId) async {
  final meta = await Supabase.instance.client
      .from('files')
      .select('thumbnail_iv')
      .eq('message_id', messageId)
      .maybeSingle();
  return meta?['thumbnail_iv'] as String?;
}



  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      floatingActionButton: (isSelectionMode || _isLoading) ? null : FloatingActionButton.extended(
        backgroundColor: AppColors.blue,
        onPressed: () async {
          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => UploadPage(folderId: widget.folderId)));
          if (res == true) _fetchFilesInitial();
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Upload", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
        ? (isGridView ? _buildGridSkeleton() : _buildListSkeleton())
        : _loadError != null
          ? _buildErrorState()
          : _files.isEmpty
            ? _buildEmptyState()
            : RefreshIndicator(
                onRefresh: _refreshFiles,
                child: isGridView ? _buildGrid(_files) : _buildList(_files),
              ),
    ), // Scaffold
    ); // ScaffoldMessenger
  }

  PreferredSizeWidget _buildAppBar() {
    if (isSelectionMode) {
      return AppBar(
        backgroundColor: AppColors.blue,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => setState(() {
            isSelectionMode = false;
            selectedFiles.clear();
          }),
        ),
        title: Text("${selectedFiles.length} selected", style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: Icon(selectedFiles.length == _files.length ? Icons.deselect : Icons.select_all, color: Colors.white),
            onPressed: _selectAll,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'make_offline':
                  _bulkMakeOffline();
                  break;
                case 'remove_offline':
                  _bulkRemoveOffline();
                  break;
                case 'download':
                  _bulkDownload();
                  break;
                case 'share':
                  _bulkShare();
                  break;
                case 'delete':
                  _bulkDelete();
                  break;
              }
            },
            itemBuilder: (_) {
              final allOffline = selectedFiles.every((f) => _offlineIds.contains(f['id']));
              return [
              PopupMenuItem(
                value: allOffline ? 'remove_offline' : 'make_offline',
                child: ListTile(
                  leading: Icon(
                    allOffline ? Icons.cloud_off_outlined : Icons.offline_pin,
                    color: allOffline ? Colors.grey : Colors.blueAccent,
                  ),
                  title: Text(allOffline ? 'Remove from offline' : 'Make available offline'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(value: 'download', child: ListTile(
                leading: Icon(Icons.download_outlined),
                title: Text('Download'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              )),
              const PopupMenuItem(value: 'share', child: ListTile(
                leading: Icon(Icons.share_outlined),
                title: Text('Share'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              )),
              const PopupMenuItem(value: 'delete', child: ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Delete', style: TextStyle(color: Colors.red)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              )),
            ];},
          ),
          const SizedBox(width: 4),
        ],
      );
    }

    

    return AppBar(
      backgroundColor: AppColors.bg,
      elevation: 0,
      leading: const BackButton(color: Colors.black),
      title: Text(
        widget.type == 'all' ? "My Drive" : widget.type.toUpperCase(),
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          icon: Icon(isGridView ? Icons.list : Icons.grid_view, color: Colors.black),
          onPressed: () => setState(() => isGridView = !isGridView),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No files here", style: TextStyle(color: Colors.grey[500], fontSize: 18)),
        ],
      ),
    );
  }

  // ── Error state with retry ──
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 64, color: Colors.red[200]),
            const SizedBox(height: 16),
            const Text("Couldn't load files",
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black54)),
            const SizedBox(height: 6),
            Text("Check your connection and try again",
                style: TextStyle(fontSize: 13, color: Colors.grey[400])),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _fetchFilesInitial,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text("Retry",
                    style: TextStyle(
                        color: AppColors.blue,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Google Drive-style Grid Skeleton ──
  Widget _buildGridSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Center(
                  child: _ShimmerRect(width: 48, height: 48, radius: 12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(child: _ShimmerRect(width: double.infinity, height: 14, radius: 6)),
                  const SizedBox(width: 8),
                  _ShimmerRect(width: 18, height: 18, radius: 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Google Drive-style List Skeleton ──
  Widget _buildListSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Thumbnail placeholder
              _ShimmerRect(width: 52, height: 52, radius: 12),
              const SizedBox(width: 14),
              // Text placeholders
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerRect(width: 140, height: 13, radius: 6),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _ShimmerRect(width: 40, height: 10, radius: 4),
                        const SizedBox(width: 8),
                        _ShimmerRect(width: 50, height: 10, radius: 4),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _ShimmerRect(width: 110, height: 10, radius: 4),
                  ],
                ),
              ),
              // More icon placeholder
              _ShimmerRect(width: 20, height: 20, radius: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> files) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = selectedFiles.contains(file);
        
        return _FileCard(
          file: file,
          isSelected: isSelected,
          isOffline: _offlineIds.contains(file['id']),
          onTap: () {
            if (isSelectionMode) {
              _toggleSelection(file);
            } else {
              _openViewer(file);
            }
          },
          onLongPress: () => _toggleSelection(file),
          onMore: () => isSelectionMode ? _toggleSelection(file) : _showOptions(file),
          getThumbnail: _getCachedThumbnail,
        );
      },
    );
  }

  Widget _buildList(List<Map<String, dynamic>> files) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = selectedFiles.contains(file);

        return _FileListItem(
          file: file,
          isSelected: isSelected,
          isOffline: _offlineIds.contains(file['id']),
          onTap: () {
            if (isSelectionMode) {
              _toggleSelection(file);
            } else {
              _openViewer(file);
            }
          },
          onLongPress: () => _toggleSelection(file),
          onMore: () => isSelectionMode ? _toggleSelection(file) : _showOptions(file),
          getThumbnail: _getCachedThumbnail,
        );
      },
    );
  }

  void _openViewer(Map<String, dynamic> file) {
    final index = _files.indexOf(file);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileViewerPage(
          files: _files,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    ).then((result) {
      // Refresh list if a file was deleted from inside the viewer
      if (result == true) _fetchFilesInitial();
    });
  }

  void _showOptions(Map<String, dynamic> file) {
    final isOffline = _offlineIds.contains(file['id']);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text("Info"),
            onTap: () { Navigator.pop(context); _showFileInfo(file); },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text("Rename"),
            onTap: () { Navigator.pop(context); _renameFile(file); },
          ),
          ListTile(
            leading: _savingOfflineIds.contains(file['id'])
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    isOffline ? Icons.cloud_off_outlined : Icons.offline_pin,
                    color: isOffline ? Colors.grey : AppColors.blue,
                  ),
            title: Text(_savingOfflineIds.contains(file['id'])
                ? "Saving…"
                : isOffline ? "Remove from offline" : "Make available offline"),
            enabled: !_savingOfflineIds.contains(file['id']),
            onTap: () {
              Navigator.pop(context);
              if (isOffline) {
                _removeOffline(file);
              } else {
                _makeOffline(file);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text("Share Securely"),
            onTap: () { Navigator.pop(context); _shareFile(file); },
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text("Download"),
            onTap: () { Navigator.pop(context); _downloadSingleFile(file); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text("Delete", style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              FileService().deleteFile(
                messageId: file['message_id'],
                supabaseId: file['id'],
                onSuccess: (_) {
                  ThumbnailCacheService.instance.evict(file['id']);
                  _fetchFilesInitial();
                },
                onError: (e) => _showSnack(SnackBar(content: Text(e))),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showFileInfo(Map<String, dynamic> file) {
    final thumbFuture = _getCachedThumbnail(file);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
            // Thumbnail / icon
            Center(
              child: FutureBuilder<Uint8List?>(
                future: thumbFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16)),
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  if (snapshot.hasData && snapshot.data != null) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(snapshot.data!, width: 90, height: 90, fit: BoxFit.cover),
                    );
                  }
                  return Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(16)),
                    child: Center(child: _FileIcon(type: file['type'] ?? '', size: 42, fileName: file['name'])),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // File name
            Center(
              child: Text(
                file['name'] ?? '-',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.category_outlined,       label: 'Type',     value: (file['type'] ?? '-').toString().toUpperCase()),
            _InfoRow(icon: Icons.storage_outlined,        label: 'Size',     value: _FileListItemState._formatSize(file['size'])),
            _InfoRow(icon: Icons.calendar_today_outlined, label: 'Uploaded', value: _FileListItemState._formatDate(file['created_at'])),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// --- Card & List Items ---

class _FileCard extends StatefulWidget {
  final Map<String, dynamic> file;
  final bool isSelected;
  final bool isOffline;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final Future<Uint8List?> Function(Map<String, dynamic>) getThumbnail;

  const _FileCard({
    required this.file, 
    required this.isSelected, 
    this.isOffline = false,
    required this.onTap, 
    required this.onLongPress,
    required this.onMore,
    required this.getThumbnail,
  });

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  late final Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = widget.getThumbnail(widget.file); // cached once
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: widget.isSelected ? Border.all(color: AppColors.blue, width: 2) : Border.all(color: Colors.transparent, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: FutureBuilder<Uint8List?>(
                    future: _thumbnailFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      }

                      if (snapshot.hasData && snapshot.data != null) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                        );
                      }

                      return Center(
                        child: _FileIcon(type: widget.file['type'], size: 48, fileName: widget.file['name']),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.file['name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey), onPressed: widget.onMore),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.isSelected)
              const Positioned(
                top: 10,
                right: 10,
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.blue,
                  child: Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ),
            if (widget.isOffline && !widget.isSelected)
              Positioned(
                bottom: 42,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 4)],
                  ),
                  child: const Icon(Icons.offline_pin, size: 15, color: AppColors.blue),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FileListItem extends StatefulWidget {
  final Map<String, dynamic> file;
  final bool isSelected;
  final bool isOffline;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final Future<Uint8List?> Function(Map<String, dynamic>) getThumbnail;

  const _FileListItem({
    required this.file,
    required this.isSelected,
    this.isOffline = false,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    required this.getThumbnail,
  });

  @override
  State<_FileListItem> createState() => _FileListItemState();
}

class _FileListItemState extends State<_FileListItem> {
  late final Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = widget.getThumbnail(widget.file);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.isSelected ? AppColors.blue.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 52,
                height: 52,
                child: FutureBuilder<Uint8List?>(
                  future: _thumbnailFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        color: Colors.grey[100],
                        child: const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasData && snapshot.data != null) {
                      return Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        width: 52,
                        height: 52,
                      );
                    }
                    return Container(
                      color: Colors.grey[100],
                      padding: const EdgeInsets.all(14),
                      child: _FileIcon(type: widget.file['type'], size: 24, fileName: widget.file['name']),
                    );
                  },
                ),
              ),
            ),
            if (widget.isSelected)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                ),
              ),
          ],
        ),
        title: Text(widget.file['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _typeColor(widget.file['type']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.file['type'].toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _typeColor(widget.file['type']),
                      ),
                    ),
                  ),
                  if (widget.file['size'] != null) ...[  
                    const SizedBox(width: 6),
                    Text(
                      _formatSize(widget.file['size']),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                  if (widget.isOffline) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.offline_pin, size: 14, color: AppColors.blue),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _formatDate(widget.file['created_at']),
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: widget.isSelected ? null : IconButton(icon: const Icon(Icons.more_vert, color: Colors.grey), onPressed: widget.onMore),
      ),
    );
  }
  static String _formatSize(dynamic bytes) {
    if (bytes == null) return '';
    final int b = bytes is int ? bytes : int.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatDate(dynamic isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate.toString()).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final period = dt.hour < 12 ? 'AM' : 'PM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ·  $hour:$min $period';
    } catch (_) {
      return '';
    }
  }

  static Color _typeColor(String type) {
    switch (type.toLowerCase()) {
      case 'image': return AppColors.blue;
      case 'video': return Colors.purple;
      case 'music': return Colors.orange;
      default: return Colors.grey;
    }
  }
}

class _FileIcon extends StatelessWidget {
  final String type;
  final double size;
  final String? fileName;

  const _FileIcon({required this.type, required this.size, this.fileName});

  @override
  Widget build(BuildContext context) {
    switch (type.toLowerCase()) {
      case 'image':
        return Icon(Icons.image_rounded, size: size, color: AppColors.blue);
      case 'video':
        return Icon(Icons.play_circle_filled_rounded, size: size, color: Colors.purple);
      case 'music':
        return Icon(Icons.music_note_rounded, size: size, color: Colors.orange);
      case 'document':
        return _buildDocIcon();
      default:
        return Icon(Icons.insert_drive_file_rounded, size: size, color: Colors.grey[600]);
    }
  }

  Widget _buildDocIcon() {
    final ext = _extFromName(fileName);
    final info = _docInfo(ext);

    // For extensions that have a recognizable label, show a styled badge
    if (info.label != null) {
      final badgeSize = size * 1.1;
      final fontSize = (size * 0.28).clamp(8.0, 16.0);
      final radius = size * 0.18;

      return SizedBox(
        width: badgeSize,
        height: badgeSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background file shape
            Icon(Icons.insert_drive_file, size: size, color: Colors.grey[300]),
            // Colored label at the bottom
            Positioned(
              bottom: size * 0.05,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: size * 0.1,
                  vertical: size * 0.04,
                ),
                decoration: BoxDecoration(
                  color: info.color,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Text(
                  info.label!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Fallback: just an icon
    return Icon(info.icon, size: size, color: info.color);
  }

  static String _extFromName(String? name) {
    if (name == null || !name.contains('.')) return '';
    return name.split('.').last.toLowerCase();
  }

  static _DocInfo _docInfo(String ext) {
    switch (ext) {
      case 'pdf':
        return _DocInfo(label: 'PDF', color: const Color(0xFFE53935), icon: Icons.picture_as_pdf_rounded);
      case 'doc':
      case 'docx':
        return _DocInfo(label: 'DOC', color: const Color(0xFF2B579A), icon: Icons.description_rounded);
      case 'xls':
      case 'xlsx':
        return _DocInfo(label: 'XLS', color: const Color(0xFF217346), icon: Icons.table_chart_rounded);
      case 'csv':
        return _DocInfo(label: 'CSV', color: const Color(0xFF217346), icon: Icons.table_chart_rounded);
      case 'ppt':
      case 'pptx':
        return _DocInfo(label: 'PPT', color: const Color(0xFFD24726), icon: Icons.slideshow_rounded);
      case 'txt':
        return _DocInfo(label: 'TXT', color: Colors.blueGrey, icon: Icons.article_rounded);
      case 'log':
        return _DocInfo(label: 'LOG', color: Colors.blueGrey, icon: Icons.article_rounded);
      case 'zip':
        return _DocInfo(label: 'ZIP', color: Colors.amber.shade700, icon: Icons.folder_zip_rounded);
      case 'rar':
        return _DocInfo(label: 'RAR', color: Colors.amber.shade700, icon: Icons.folder_zip_rounded);
      case '7z':
        return _DocInfo(label: '7Z', color: Colors.amber.shade700, icon: Icons.folder_zip_rounded);
      case 'tar':
      case 'gz':
        return _DocInfo(label: ext.toUpperCase(), color: Colors.amber.shade700, icon: Icons.folder_zip_rounded);
      case 'html':
      case 'htm':
        return _DocInfo(label: 'HTML', color: const Color(0xFFE44D26), icon: Icons.code_rounded);
      case 'css':
        return _DocInfo(label: 'CSS', color: const Color(0xFF264DE4), icon: Icons.code_rounded);
      case 'js':
        return _DocInfo(label: 'JS', color: const Color(0xFFF7DF1E), icon: Icons.code_rounded);
      case 'json':
        return _DocInfo(label: 'JSON', color: Colors.indigo, icon: Icons.code_rounded);
      case 'xml':
        return _DocInfo(label: 'XML', color: Colors.indigo, icon: Icons.code_rounded);
      case 'apk':
        return _DocInfo(label: 'APK', color: const Color(0xFF3DDC84), icon: Icons.android_rounded);
      case 'exe':
        return _DocInfo(label: 'EXE', color: Colors.blueGrey, icon: Icons.desktop_windows_rounded);
      case 'msi':
        return _DocInfo(label: 'MSI', color: Colors.blueGrey, icon: Icons.desktop_windows_rounded);
      default:
        return _DocInfo(label: null, color: Colors.teal, icon: Icons.description_rounded);
    }
  }
}

class _DocInfo {
  final String? label;
  final Color color;
  final IconData icon;
  const _DocInfo({required this.label, required this.color, required this.icon});
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing shimmer rectangle (Google Drive skeleton style) ──
class _ShimmerRect extends StatefulWidget {
  final double width, height, radius;
  const _ShimmerRect({
    required this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  State<_ShimmerRect> createState() => _ShimmerRectState();
}

class _ShimmerRectState extends State<_ShimmerRect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.06, end: 0.14).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(_opacity.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}