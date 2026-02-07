import 'dart:ui';
import 'package:flutter/material.dart';
import 'add_options.dart'; // ✅ THIS IS THE KEY FIX

class BottomNavBar extends StatelessWidget {
  final VoidCallback onHome;
  final VoidCallback onCreateFolder;
  final VoidCallback onFiles;
  final VoidCallback onProfile;

  const BottomNavBar({
    super.key,
    required this.onHome,
    required this.onCreateFolder,
    required this.onFiles,
    required this.onProfile,
  });

  /// ➕ SHOW ADD OPTIONS (UPLOAD / CREATE FOLDER)
  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              /// 📤 UPLOAD FILE → LOCATION PICKER (FIXED)
              ListTile(
                leading: const Icon(Icons.upload_file, color: Colors.blue),
                title: const Text("Upload file"),
                onTap: () {
                  Navigator.pop(context);
                  showUploadLocationPicker(context); // ✅ GOOGLE DRIVE BEHAVIOR
                },
              ),

              /// 📁 CREATE FOLDER
              ListTile(
                leading:
                    const Icon(Icons.create_new_folder, color: Colors.green),
                title: const Text("Create folder"),
                onTap: () {
                  Navigator.pop(context);
                  onCreateFolder();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.35),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white30),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.home),
                    onPressed: onHome,
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder),
                    onPressed: onFiles,
                  ),

                  /// ➕ ADD BUTTON (UNCHANGED UI)
                  GestureDetector(
                    onTap: () => _showAddOptions(context),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),

                  IconButton(
                    icon: const Icon(Icons.notifications),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.person),
                    onPressed: onProfile,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
