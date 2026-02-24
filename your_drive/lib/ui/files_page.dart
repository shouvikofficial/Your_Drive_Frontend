import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';
import '../config/env.dart';
import '../services/file_service.dart';
import '../services/download_service.dart';
import '../services/vault_service.dart';
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
  
  final Set<Map<String, dynamic>> selectedFiles = {};
  bool isSelectionMode = false;

  // Thumbnail cache: keyed by file id so futures survive scroll recycling
  final Map<dynamic, Future<Uint8List?>> _thumbnailCache = {};

  Future<Uint8List?> _getCachedThumbnail(Map<String, dynamic> file) {
    final key = file['id'];
    return _thumbnailCache.putIfAbsent(key, () => _getThumbnail(file));
  }

  @override
  void initState() {
    super.initState();
    _fetchFilesInitial();
  }

  Future<void> _fetchFilesInitial() async {
    setState(() => _isLoading = true);
    await _loadData();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshFiles() async {
    await _loadData();
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    try {
      final supabase = Supabase.instance.client;
      var query = supabase.from('files').select();

      if (widget.type != 'all') {
        query = query.eq('type', widget.type);
      } else if (widget.folderId != null) {
        query = query.eq('folder_id', widget.folderId!);
      }

      final response = await query.order('created_at', ascending: false);
      _files = List<Map<String, dynamic>>.from(response);
      _thumbnailCache.clear();
      selectedFiles.clear();
      isSelectionMode = false;
    } catch (e) {
      debugPrint("Error loading files: $e");
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
    final controller = TextEditingController(text: file['name']);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'File name',
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

    if (newName == null || newName.isEmpty || newName == file['name']) return;

    final resolvedName = _resolveUniqueName(newName, file['id'] as String);

    try {
      await Supabase.instance.client
          .from('files')
          .update({'name': resolvedName})
          .eq('id', file['id']);

      if (resolvedName != newName && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved as "$resolvedName" to avoid duplicates.'),
          ),
        );
      }

      await _loadData();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e'), backgroundColor: Colors.red),
        );
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
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
          await FileService().deleteFile(
            messageId: file['message_id'],
            supabaseId: file['id'],
            onSuccess: (_) {},
            onError: (e) {},
          );
        }
      } finally {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await _loadData();
        if (mounted) setState(() {}); 
      }
    }
  }

  Future<void> _bulkDownload() async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Downloading ${selectedFiles.length} files..."))
    );
    for (var file in selectedFiles) {
      await DownloadService.downloadFile(file['message_id'].toString(), file['name']);
    }
    setState(() {
      selectedFiles.clear();
      isSelectionMode = false;
    });
  }

  // --- Sharing & Decryption ---

 Future<void> _shareFile(Map<String, dynamic> file) async {
  try {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Preparing secure file...")),
    );

    final supabase = Supabase.instance.client;

    final fileData = await supabase
        .from('files')
        .select('iv, chunk_size, total_chunks')
        .eq('message_id', file['message_id'])
        .maybeSingle();

    if (fileData == null) throw Exception("Metadata missing");

    final ivBase64 = fileData['iv'];
    final int chunkSize = fileData['chunk_size'];
    final int totalChunks = fileData['total_chunks'];

    final url =
        "${Env.backendBaseUrl}/api/file/${file['message_id']}";

    // 🔥 Step 1: Download FULL encrypted file
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception("Download failed");
    }

    final encryptedBytes = response.bodyBytes;

    // 🔥 Step 2: Decrypt properly
    final decryptedFile = await _decryptFullFile(
      encryptedBytes,
      ivBase64,
      chunkSize,
      totalChunks,
      file['name'],
    );

    final box = context.findRenderObject() as RenderBox?;

    await Share.shareXFiles(
      [XFile(decryptedFile.path)],
      sharePositionOrigin:
          box!.localToGlobal(Offset.zero) & box.size,
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Share failed"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<File> _decryptFullFile(
  List<int> encryptedBytes,
  String ivBase64,
  int chunkSize,
  int totalChunks,
  String fileName,
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

  final dir = await getTemporaryDirectory();
  final file = File("${dir.path}/$fileName");
  await file.writeAsBytes(output.toBytes());

  return file;
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
    return Scaffold(
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
        ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
        : _files.isEmpty 
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _refreshFiles,
              child: isGridView ? _buildGrid(_files) : _buildList(_files),
            ),
    );
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
          IconButton(icon: const Icon(Icons.download, color: Colors.white), onPressed: _bulkDownload),
          IconButton(icon: const Icon(Icons.delete, color: Colors.white), onPressed: _bulkDelete),
          const SizedBox(width: 8),
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileViewerPage(
          messageId: file['message_id'].toString(),
          fileName: file['name'],
          type: file['type'],
        ),
      ),
    );
  }

  void _showOptions(Map<String, dynamic> file) {
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
            leading: const Icon(Icons.share_outlined),
            title: const Text("Share Securely"),
            onTap: () { Navigator.pop(context); _shareFile(file); },
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text("Download"),
            onTap: () { Navigator.pop(context); DownloadService.downloadFile(file['message_id'].toString(), file['name']); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text("Delete", style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              FileService().deleteFile(
                messageId: file['message_id'],
                supabaseId: file['id'],
                onSuccess: (_) => _fetchFilesInitial(),
                onError: (e) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e))),
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
                    child: Center(child: _FileIcon(type: file['type'] ?? '', size: 42)),
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
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final Future<Uint8List?> Function(Map<String, dynamic>) getThumbnail;

  const _FileCard({
    required this.file, 
    required this.isSelected, 
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
                        child: _FileIcon(type: widget.file['type'], size: 48),
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
          ],
        ),
      ),
    );
  }
}

class _FileListItem extends StatefulWidget {
  final Map<String, dynamic> file;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final Future<Uint8List?> Function(Map<String, dynamic>) getThumbnail;

  const _FileListItem({
    required this.file,
    required this.isSelected,
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
                      child: _FileIcon(type: widget.file['type'], size: 24),
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

  const _FileIcon({required this.type, required this.size});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (type.toLowerCase()) {
      case 'image':
        icon = Icons.image_rounded;
        color = AppColors.blue;
        break;
      case 'video':
        icon = Icons.play_circle_filled_rounded;
        color = Colors.purple;
        break;
      case 'music':
        icon = Icons.music_note_rounded;
        color = Colors.orange;
        break;
      default:
        icon = Icons.insert_drive_file_rounded;
        color = Colors.grey[600]!;
    }

    return Icon(icon, size: size, color: color);
  }
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