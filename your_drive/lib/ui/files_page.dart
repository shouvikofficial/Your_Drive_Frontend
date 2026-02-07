import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';
import '../config/env.dart';
import '../services/file_service.dart';
import '../services/download_service.dart';
import 'upload_page.dart'; // Import your upload page

class FilesPage extends StatefulWidget {
  final String type; // image, video, music, app, all
  final String? folderId; // ✅ ADD THIS: To know which folder we are in

  const FilesPage({
    super.key,
    required this.type,
    this.folderId, // ✅ OPTIONAL
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
    filesFuture = fetchFiles();
  }

  /// 🔄 REFRESH FILES
  void _refreshFiles() {
    setState(() {
      filesFuture = fetchFiles();
    });
  }

  /// 🔥 FETCH FILES (NOW FILTERS BY FOLDER)
  Future<List<Map<String, dynamic>>> fetchFiles() async {
    final supabase = Supabase.instance.client;
    
    // Start building the query
    var query = supabase
        .from('files')
        .select();

    // ✅ FIX: Filter by folder_id if we are inside a folder
    if (widget.folderId != null) {
      query = query.eq('folder_id', widget.folderId!);
    } 
    // If not inside a specific folder (e.g., "Photos" category), 
    // typically you might want to show files with NO folder or ALL files.
    // This depends on your logic. Usually, "Photos" shows all photos globally.
    
    final response = await query.order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// 🗑 DELETE FILE
  Future<void> deleteFile(Map<String, dynamic> file) async {
    try {
      await FileService.deleteFile(
        messageId: file['message_id'],
        rowId: file['id'],
      );
      if (!mounted) return;
      _refreshFiles(); // Refresh list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Deleted successfully")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Delete failed")),
      );
    }
  }

  /// ⚠ CONFIRM DELETE
  void _confirmDelete(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete file?"),
        content: const Text("This file will be permanently deleted."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
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

  /// ⬇ DOWNLOAD
  void _confirmDownload(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Download file?"),
        content: Text(file['name'] ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await DownloadService.downloadFile(
                  file['file_id'],
                  file['name'],
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Download started")),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Download failed")),
                );
              }
            },
            child: const Text("Download"),
          ),
        ],
      ),
    );
  }

  /// 📂 ACTION SHEET
  void _showFileActions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text("Download"),
              onTap: () {
                Navigator.pop(context);
                _confirmDownload(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete", style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 600 ? 4 : 2;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        title: Text(
          widget.type == 'all' && widget.folderId != null 
              ? "Folder Content" 
              : widget.type.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
      ),
      
      // ✅ ADD FLOATING BUTTON TO UPLOAD HERE
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.blue,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UploadPage(folderId: widget.folderId), // Pass ID!
            ),
          ).then((value) {
            if (value == true) {
              _refreshFiles(); // Refresh after upload
            }
          });
        },
      ),

      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: filesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No files found"));
          }

          final files = snapshot.data!
              .where((f) => widget.type == 'all' || f['type'] == widget.type)
              .toList();

          if (files.isEmpty) {
            return const Center(child: Text("No files in this category"));
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                final fileId = file['file_id'];
                final thumbId = file['thumbnail_id'];

                return GestureDetector(
                  onLongPress: () => _showFileActions(file),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (file['type'] == 'image' && fileId != null)
                            Image.network("$backendBaseUrl/file/$fileId", fit: BoxFit.cover)
                          else if (file['type'] == 'video' && thumbId != null)
                            Image.network("$backendBaseUrl/file/$thumbId", fit: BoxFit.cover)
                          else
                            Center(
                              child: Icon(
                                _iconForType(file['type']),
                                size: 48,
                                color: Colors.black45,
                              ),
                            ),
                          if (file['type'] == 'video')
                            const Center(child: Icon(Icons.play_circle_fill, size: 40, color: Colors.white)),
                          
                          Positioned(
                            bottom: 0, left: 0, right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              color: Colors.black54,
                              child: Text(
                                file['name'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  IconData _iconForType(String type) {
    switch (type) {
      case 'image': return Icons.image;
      case 'video': return Icons.videocam;
      case 'music': return Icons.music_note;
      case 'app': return Icons.apps;
      default: return Icons.insert_drive_file;
    }
  }
}