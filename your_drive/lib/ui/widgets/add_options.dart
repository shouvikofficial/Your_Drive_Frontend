import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../upload_page.dart'; // Ensure this path matches your file structure

void showUploadLocationPicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true, // ✅ Allows the sheet to be taller if needed
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) {
      final supabase = Supabase.instance.client;

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5, // Start at 50% height
        maxChildSize: 0.9,     // Can be dragged up to 90%
        minChildSize: 0.3,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController, // ✅ Connects scrolling to the sheet
            padding: const EdgeInsets.all(16),
            children: [
              /// HEADER
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
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
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

              /// 📂 USER FOLDERS (DYNAMIC)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: supabase
                    .from('folders')
                    .select()
                    .order('created_at', ascending: false), // Newest first
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text("No folders created yet")),
                    );
                  }

                  // ✅ Safe Data Casting
                  final folders = List<Map<String, dynamic>>.from(snapshot.data!);

                  return ListView.separated(
                    shrinkWrap: true, // ✅ Vital for nesting inside ListView
                    physics: const NeverScrollableScrollPhysics(), // Let the parent handle scrolling
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
              const SizedBox(height: 20),
            ],
          );
        },
      );
    },
  );
}