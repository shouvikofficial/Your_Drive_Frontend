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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Decrypting & Preparing..."),
        duration: Duration(seconds: 1),
      ));

      final url = "${Env.backendBaseUrl}/api/file/${file['message_id']}";
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) throw Exception("Download failed");

      final decryptedBytes = await _decryptFile(response.bodyBytes, file['iv']);
      final tempDir = await getTemporaryDirectory();
      final tempFile = await File('${tempDir.path}/${file['name']}').create();
      await tempFile.writeAsBytes(decryptedBytes);

      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Decryption failed"), backgroundColor: Colors.red));
      }
    }
  }

 Future<List<int>> _decryptFile(List<int> encryptedBytes, String? ivBase64) async {
  if (ivBase64 == null || ivBase64.isEmpty) {
    throw Exception("Missing IV");
  }

  final baseNonce = base64Decode(ivBase64);
  final secretKey = await VaultService().getSecretKey();
  final algorithm = AesGcm.with256bits();

  const chunkSize = 5 * 1024 * 1024 + 16; // encrypted chunk = data + MAC
  int offset = 0;

  final output = BytesBuilder();

  while (offset < encryptedBytes.length) {
    final end = (offset + chunkSize > encryptedBytes.length)
        ? encryptedBytes.length
        : offset + chunkSize;

    final chunk = encryptedBytes.sublist(offset, end);

    // split MAC
    final macBytes = chunk.sublist(chunk.length - 16);
    final cipherText = chunk.sublist(0, chunk.length - 16);

    // derive nonce same as upload
    final chunkIndex = offset ~/ chunkSize;
    final nonce = Uint8List.fromList(baseNonce);
    for (int i = 0; i < 4; i++) {
      nonce[nonce.length - 1 - i] ^= (chunkIndex >> (8 * i)) & 0xff;
    }

    final decrypted = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: secretKey,
    );

    output.add(decrypted);
    offset = end;
  }

  return output.toBytes();
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
}

// --- Card & List Items ---

class _FileCard extends StatelessWidget {
  final Map<String, dynamic> file;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  const _FileCard({
    required this.file, 
    required this.isSelected, 
    required this.onTap, 
    required this.onLongPress,
    required this.onMore
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? Border.all(color: AppColors.blue, width: 2) : Border.all(color: Colors.transparent, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(child: _FileIcon(type: file['type'], size: 48)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 4, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          file['name'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey), onPressed: onMore),
                    ],
                  ),
                ),
              ],
            ),
            if (isSelected)
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

class _FileListItem extends StatelessWidget {
  final Map<String, dynamic> file;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  const _FileListItem({
    required this.file, 
    required this.isSelected, 
    required this.onTap, 
    required this.onLongPress,
    required this.onMore
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.blue.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              child: _FileIcon(type: file['type'], size: 24),
            ),
            if (isSelected)
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
        title: Text(file['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(file['type'].toUpperCase(), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        trailing: isSelected ? null : IconButton(icon: const Icon(Icons.more_vert, color: Colors.grey), onPressed: onMore),
      ),
    );
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