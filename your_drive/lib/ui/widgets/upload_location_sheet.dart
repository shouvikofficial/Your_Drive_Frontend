import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../upload_page.dart'; // ✅ Imports UploadPage correctly

void showUploadLocationPicker(BuildContext context) {
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
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UploadPage(folderId: null),
                      ),
                    );
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
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UploadPage(
                                  folderId: folder['id'],
                                ),
                              ),
                            );
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