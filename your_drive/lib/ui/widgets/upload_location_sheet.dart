import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/upload_manager.dart';
import '../../services/saf_service.dart';

void showUploadLocationPicker(BuildContext context) {
  Future<void> _pickAndUploadFiles(BuildContext ctx, String? folderId, String folderName) async {
    Navigator.pop(ctx); // Close the BottomSheet first

    final files = await SafService.pickFiles();
    if (files == null || files.isEmpty) return;

    final manager = UploadManager();
    final newItems = <UploadItem>[];

    for (final file in files) {
      final item = await manager.addSafFile(
        uri: file['uri'],
        name: file['name'],
        size: file['size'],
        folderId: folderId,
        folderName: folderName,
      );
      if (item != null) newItems.add(item);
    }

    if (newItems.isNotEmpty) {
      if (manager.isUploading) {
        manager.uploadAdditionalItems(newItems);
      } else {
        manager.startBatchUpload();
      }
    }
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true, // ✅ Allows the sheet to expand fully
    backgroundColor: Colors.transparent,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 0.5, // Opens at 50% height
        maxChildSize: 0.9,     // Can drag up to 90%
        minChildSize: 0.3,     // Won't shrink below 30%
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollController, // ✅ Enables scrolling
              padding: const EdgeInsets.all(16),
              children: [
                /// DRAG HANDLE
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                
                const Text(
                  "Upload to",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                /// 📁 ROOT (MY DRIVE)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.cloud_upload, color: Colors.blue),
                  ),
                  title: const Text("My Drive (Root)"),
                  subtitle: const Text("Upload outside of any folder"),
                  onTap: () {
                    _pickAndUploadFiles(context, null, 'My Drive');
                  },
                ),

                const Divider(height: 30),

                const Text(
                  "Or choose a folder:",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),

                /// 📂 USER FOLDERS
                FutureBuilder(
                  future: Supabase.instance.client
                      .from('folders')
                      .select('id, name')
                      .order('created_at', ascending: false),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text("No folders created yet")),
                      );
                    }

                    final folders = snapshot.data as List;

                    // ✅ ListView.separated handles long lists efficiently
                    return ListView.separated(
                      shrinkWrap: true, 
                      physics: const NeverScrollableScrollPhysics(), // Parent ListView handles scroll
                      itemCount: folders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.folder, color: Colors.orange),
                          ),
                          title: Text(
                            folder['name'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onTap: () {
                            _pickAndUploadFiles(context, folder['id'], folder['name']);
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}