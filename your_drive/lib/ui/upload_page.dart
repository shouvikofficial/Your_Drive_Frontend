import 'dart:io';
import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../theme/app_colors.dart';

class UploadPage extends StatefulWidget {
  final String? folderId; 

  const UploadPage({
    super.key,
    this.folderId, 
  });

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  File? selectedFile;
  bool uploading = false;
  
  String folderName = "My Drive"; 

  final String telegramBotUploadUrl = "${Env.backendBaseUrl}/upload";

  @override
  void initState() {
    super.initState();
    _fetchFolderName();
  }

  /// 📂 FETCH FOLDER NAME
  Future<void> _fetchFolderName() async {
    if (widget.folderId == null) return; 

    final supabase = Supabase.instance.client;
    try {
      final data = await supabase
          .from('folders')
          .select('name')
          .eq('id', widget.folderId!)
          .single();
      
      if (mounted) {
        setState(() {
          folderName = data['name'];
        });
      }
    } catch (e) {
      debugPrint("Error fetching folder name: $e");
    }
  }

  /// 📂 PICK FILE
  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null) return;

    final path = result.files.single.path;
    if (path == null) return;

    setState(() => selectedFile = File(path));
  }

  /// 🚀 UPLOAD FILE
  Future<void> uploadFile() async {
    if (selectedFile == null) return;

    setState(() => uploading = true);

    try {
      final request =
          http.MultipartRequest('POST', Uri.parse(telegramBotUploadUrl));

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          selectedFile!.path,
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception("Upload failed: ${response.statusCode}");
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;

      final String telegramFileId = decoded['file_id'];
      final String? telegramThumbId = decoded['thumbnail_id'];
      final int telegramMessageId = decoded['message_id'];
      final String fileType = decoded['type'];

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser!;

      // ✅ GET FILE SIZE
      final int fileSize = await selectedFile!.length(); 

      /// ✅ SAVE TO DB (WITH SIZE)
      await supabase.from('files').insert({
        'user_id': user.id,
        'file_id': telegramFileId,
        'thumbnail_id': telegramThumbId,
        'message_id': telegramMessageId,
        'name': selectedFile!.path.split('/').last,
        'type': fileType,
        'folder_id': widget.folderId,
        'size': fileSize, // ✅ Added size here
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Uploaded successfully")),
      );

      Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint("UPLOAD ERROR: $e");
      debugPrintStack(stackTrace: st);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Upload failed")),
      );
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Upload"),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 90,
                        width: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.blue, AppColors.purple],
                          ),
                        ),
                        child: const Icon(
                          Icons.cloud_upload,
                          size: 42,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      const Text(
                        "Upload your file",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      /// SHOW FOLDER NAME
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.folderId == null ? Icons.home : Icons.folder_open,
                              size: 16,
                              color: Colors.black54,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Saving to: $folderName",
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),
                      
                      OutlinedButton.icon(
                        onPressed: pickFile,
                        icon: const Icon(Icons.attach_file),
                        label: const Text("Choose file"),
                      ),
                      const SizedBox(height: 18),
                      
                      if (selectedFile != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white70,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.insert_drive_file),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  selectedFile!.path.split('/').last,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 28),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              uploading || selectedFile == null
                                  ? null
                                  : uploadFile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: uploading
                              ? const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                )
                              : const Text("Upload"),
                        ),
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