import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_colors.dart';

class CreateFolderPage extends StatefulWidget {
  final String? currentFolderId;

  const CreateFolderPage({
    super.key, 
    this.currentFolderId
  });

  @override
  State<CreateFolderPage> createState() => _CreateFolderPageState();
}

class _CreateFolderPageState extends State<CreateFolderPage> {
  final TextEditingController nameController = TextEditingController();
  bool creating = false;

  /// 📁 CREATE FOLDER LOGIC
  Future<void> createFolder() async {
    final rawName = nameController.text.trim();

    if (rawName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Folder name required"), backgroundColor: Colors.red),
      );
      return;
    }

    // ✅ FORCE CAPITALIZATION (First Letter Upper, rest as typed)
    final name = rawName.length > 1
        ? rawName[0].toUpperCase() + rawName.substring(1)
        : rawName.toUpperCase();

    setState(() => creating = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) throw Exception("Not logged in");

      // 1. 🔍 CHECK FOR DUPLICATES (Case-Insensitive)
      var checkQuery = supabase
          .from('folders')
          .select('id')
          .eq('user_id', user.id)
          .ilike('name', name); // Check against the capitalized name

      if (widget.currentFolderId != null) {
        checkQuery = checkQuery.eq('folder_id', widget.currentFolderId!);
      } else {
        checkQuery = checkQuery.isFilter('folder_id', null);
      }

      final existing = await checkQuery.maybeSingle();

      if (existing != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Folder '$name' already exists."), 
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => creating = false);
        return; 
      }

      // 2. 🚀 CREATE FOLDER
      await supabase.from('folders').insert({
        'user_id': user.id,
        'name': name, // Saves the Capitalized version
        'folder_id': widget.currentFolderId,
      });

      if (!mounted) return;

      Navigator.pop(context, true);

    } catch (e) {
      if (!mounted) return;
      String errorMsg = e.toString();
      // Friendly error if migration wasn't run
      if (errorMsg.contains("folder_id does not exist")) {
        errorMsg = "Database Error: Missing 'folder_id' column. Please run the SQL script.";
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => creating = false);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        title: const Text("New Folder", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 📁 ICON
                      Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          color: AppColors.blue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.create_new_folder_rounded, size: 40, color: AppColors.blue),
                      ),
                      
                      const SizedBox(height: 24),

                      const Text(
                        "Create New Folder",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Text(
                        widget.currentFolderId == null 
                            ? "This will be added to your My Drive"
                            : "This will be added to the current folder",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),

                      const SizedBox(height: 32),

                      /// ✏️ INPUT FIELD
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        // ✅ KEY CHANGE: Defaults keyboard to Uppercase
                        textCapitalization: TextCapitalization.sentences, 
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: "Folder Name",
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: AppColors.blue, width: 2),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      /// ✅ ACTION BUTTONS
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.grey[600],
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: creating ? null : createFolder,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.blue,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: creating
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text("Create", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}