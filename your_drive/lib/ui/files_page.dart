import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../config/env.dart';
import '../services/file_service.dart';
import '../services/download_service.dart';
import 'upload_page.dart';
import 'file_viewer_page.dart'; // ✅ Added Import

class FilesPage extends StatefulWidget {
  final String type; // 'all', 'image', 'video', etc.
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
  late Future<List<Map<String, dynamic>>> filesFuture;
  final backendBaseUrl = Env.backendBaseUrl;

  @override
  void initState() {
    super.initState();
    _refreshFiles();
  }

  void _refreshFiles() {
    setState(() {
      filesFuture = fetchFiles();
    });
  }

  // ============================================================
  // 🔥 FETCH FILES
  // ============================================================
  Future<List<Map<String, dynamic>>> fetchFiles() async {
    final supabase = Supabase.instance.client;
    var query = supabase.from('files').select();

    if (widget.type != 'all') {
      query = query.eq('type', widget.type);
    } else {
      if (widget.folderId != null) {
        query = query.eq('folder_id', widget.folderId!);
      }
    }

    final response = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // ============================================================
  // LOGIC: DELETE & DOWNLOAD
  // ============================================================
  Future<void> deleteFile(Map<String, dynamic> file) async {
    await FileService().deleteFile(
      messageId: file['message_id'] as int,
      supabaseId: file['id'] as String,
      onSuccess: (msg) {
        if (!mounted) return;
        _refreshFiles();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      },
      onError: (err) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
      },
    );
  }

  void _showFileActions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  _buildFileIcon(file['type'], 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _getCleanFileName(file['name']),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppColors.blue),
              title: const Text("Download", style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _confirmDownload(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(file);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _confirmDownload(Map<String, dynamic> file) {
    // Direct download start
    DownloadService.downloadFile(file['message_id'].toString(), file['name']);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download started...")));
  }

  void _confirmDelete(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete file?"),
        content: const Text("This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              deleteFile(file);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _getCleanFileName(String? rawName) {
    if (rawName == null) return 'Untitled';
    return rawName.split('/').last.split('\\').last;
  }

  // ============================================================
  // UI HELPERS
  // ============================================================
  Widget _buildFileIcon(String? type, double size) {
    IconData icon = Icons.insert_drive_file;
    Color color = Colors.grey;

    if (type == 'image') { icon = Icons.image; color = AppColors.blue; }
    else if (type == 'video') { icon = Icons.play_circle_fill; color = AppColors.purple; }
    else if (type == 'music') { icon = Icons.music_note; color = Colors.green; }
    else if (type == 'app') { icon = Icons.android; color = Colors.orange; }

    return Icon(icon, size: size, color: color);
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    // Responsive Grid: 2 columns on mobile, 5 on tablet/desktop
    final crossAxisCount = MediaQuery.of(context).size.width > 600 ? 5 : 2;

    return Scaffold(
      backgroundColor: AppColors.bg, 
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        title: Text(
          widget.type == 'all' ? (widget.folderId != null ? "Folder" : "My Drive") : widget.type.toUpperCase(),
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {}, 
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.blue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Upload", style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UploadPage(folderId: widget.folderId)),
          );
          if (result == true) _refreshFiles();
        },
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: filesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
             return Center(child: Text("Error loading files", style: TextStyle(color: Colors.grey[600])));
          }

          final files = snapshot.data ?? [];

          if (files.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open_rounded, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("No files here", style: TextStyle(fontSize: 18, color: Colors.grey[500])),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refreshFiles(),
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85, // Aspect ratio for "Card" look
              ),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final messageId = file['message_id'];
                final displayName = _getCleanFileName(file['name']);
                final type = file['type'] ?? 'document';
                
                final isVisual = type == 'image' || type == 'video';

                return GestureDetector(
                  // 🚀 UPDATED: Tap to Open Viewer, Long Press for Actions
                  onTap: () {
                    if (isVisual && messageId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FileViewerPage(
                            messageId: messageId.toString(),
                            fileName: displayName,
                            type: type,
                          ),
                        ),
                      );
                    } else {
                      // For non-visual files (docs, music), just show actions
                      _showFileActions(file);
                    }
                  },
                  onLongPress: () => _showFileActions(file),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withOpacity(0.15)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 🖼️ THUMBNAIL AREA (Top 70%)
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              child: Center(
                                child: isVisual && messageId != null
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          // 🚀 KEY CHANGE: Uses /thumbnail/ endpoint
                                          Image.network(
                                            "$backendBaseUrl/api/thumbnail/$messageId",
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => _buildFileIcon(type, 40),
                                            loadingBuilder: (c, w, p) => p == null ? w : const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                                          ),
                                          if (type == 'video')
                                            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40)),
                                        ],
                                      )
                                    : _buildFileIcon(type, 40),
                              ),
                            ),
                          ),
                        ),

                        // 📄 FOOTER AREA (Bottom 30%)
                        Expanded(
                          flex: 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              children: [
                                // Small Type Icon
                                _buildFileIcon(type, 16),
                                const SizedBox(width: 8),
                                
                                // Filename
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                                // 3-Dot Menu
                                InkWell(
                                  onTap: () => _showFileActions(file),
                                  borderRadius: BorderRadius.circular(20),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4.0),
                                    child: Icon(Icons.more_vert, size: 18, color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}