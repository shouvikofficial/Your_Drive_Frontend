import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart'; // ✅ Added for SHA-256
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart' as dio;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../theme/app_colors.dart';

// 📦 HELPER CLASS FOR QUEUE ITEMS
class UploadItem {
  final String id;
  final File file;
  double progress;
  String status; // 'waiting', 'uploading', 'done', 'error', 'exists' // ✅ Added 'exists'

  UploadItem({
    required this.file,
    this.progress = 0.0,
    this.status = 'waiting',
  }) : id = DateTime.now().microsecondsSinceEpoch.toString() + Random().nextInt(1000).toString();
}

class UploadPage extends StatefulWidget {
  final String? folderId;

  const UploadPage({super.key, this.folderId});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  // 📋 THE QUEUE
  List<UploadItem> uploadQueue = [];
  bool isUploadingBatch = false;
  String folderName = "My Drive";

  final String chunkUploadUrl = "${Env.backendBaseUrl}/api/upload-chunk";

  @override
  void initState() {
    super.initState();
    _fetchFolderName();
  }

  Future<void> _fetchFolderName() async {
    if (widget.folderId == null || widget.folderId == 'root' || widget.folderId == '') {
      setState(() => folderName = "My Drive");
      return;
    }

    final supabase = Supabase.instance.client;
    try {
      final data = await supabase.from('folders').select('name').eq('id', widget.folderId!).single();
      if (mounted) setState(() => folderName = data['name']);
    } catch (_) {}
  }

  // 📂 PICK MULTIPLE FILES
  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true, 
      withData: false,
    );

    if (result == null) return;

    setState(() {
      uploadQueue.addAll(
        result.paths.where((path) => path != null).map((path) => UploadItem(file: File(path!))),
      );
    });
  }

  // 🚀 START BATCH UPLOAD (SEQUENTIAL)
  Future<void> startBatchUpload() async {
    if (isUploadingBatch) return;

    setState(() => isUploadingBatch = true);

    for (var item in uploadQueue) {
      // ✅ SKIP IF FINISHED OR ALREADY EXISTS
      if (item.status == 'done' || item.status == 'exists') continue; 

      await _uploadSingleItem(item);
      
      if (!mounted) break; 
    }

    if (mounted) {
      setState(() => isUploadingBatch = false);
    }
  }

  // ☁️ UPLOAD SINGLE ITEM (CHUNKED WITH DEDUPLICATION)
  Future<void> _uploadSingleItem(UploadItem item) async {
    setState(() => item.status = 'uploading');

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // ✅ STEP 1: Generate SHA-256 Hash
      final String fileHash = await _getFileHash(item.file);

      // ✅ STEP 2: Check for existing file with this hash in Supabase
      final existingFile = await supabase
          .from('files')
          .select()
          .eq('hash', fileHash)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingFile != null) {
        // ✅ DUPLICATE FOUND: Strictly ignore upload and database insert
        if (mounted) {
          setState(() {
            item.progress = 1.0;
            item.status = 'exists'; // Set custom status for UI
          });
        }
        return; // 🔥 EXIT: No upload, no new row.
      }

      // 🚀 NEW FILE: Proceed with chunked upload
      final dioClient = dio.Dio();
      final fileName = item.file.path.split(Platform.pathSeparator).last;
      final fileSize = await item.file.length();
      
      const chunkSize = 5 * 1024 * 1024;
      final totalChunks = (fileSize / chunkSize).ceil();
      final uploadId = "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";
      final raf = item.file.openSync();

      try {
        for (int i = 0; i < totalChunks; i++) {
          final start = i * chunkSize;
          final end = min(start + chunkSize, fileSize);
          final length = end - start;

          raf.setPositionSync(start);
          final chunkBytes = raf.readSync(length);

          int retry = 0;
          bool chunkSuccess = false;
          dio.Response? response;

          while (!chunkSuccess && retry < 5) {
            try {
              final formData = dio.FormData.fromMap({
                "file": dio.MultipartFile.fromBytes(chunkBytes, filename: fileName),
                "chunk_index": i,
                "total_chunks": totalChunks,
                "file_name": fileName,
                "upload_id": uploadId,
              });

              response = await dioClient.post(
                chunkUploadUrl,
                data: formData,
                options: dio.Options(sendTimeout: const Duration(minutes: 30)),
              );
              chunkSuccess = true;
            } catch (e) {
              retry++;
              await Future.delayed(const Duration(seconds: 2));
            }
          }

          if (!chunkSuccess) throw Exception("Chunk failed");

          if (mounted) {
            setState(() {
              item.progress = (i + 1) / totalChunks;
            });
          }

          if (i == totalChunks - 1 && response?.statusCode == 200) {
            await _saveToSupabase(response?.data ?? {}, fileName, fileSize, fileHash);
          }
        }

        if (mounted) setState(() => item.status = 'done');

      } finally {
        raf.closeSync();
      }

    } catch (e) {
      debugPrint("Item failed: $e");
      if (mounted) setState(() => item.status = 'error');
    }
  }

  // ✅ SHA-256 HASH GENERATOR
  Future<String> _getFileHash(File file) async {
    final stream = file.openRead();
    final hash = await sha256.bind(stream).first;
    return hash.toString();
  }

  Future<void> _saveToSupabase(Map data, String name, int size, String hash) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final String? folderIdToSave = 
        (widget.folderId == 'root' || widget.folderId == '') ? null : widget.folderId;
    
    final String correctType = _getFileType(name, data['type']);

    try {
      await supabase.from('files').insert({
        'user_id': user.id,
        'file_id': data['file_id'], 
        'message_id': data['message_id'],
        'name': name,
        'type': correctType, 
        'folder_id': folderIdToSave, 
        'size': size,
        'hash': hash, 
      });
    } catch (_) {}
  }

  String _getFileType(String fileName, String? serverType) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) return 'image';
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'aac'].contains(ext)) return 'music';
    if (['apk', 'exe', 'dmg'].contains(ext)) return 'app';
    return serverType ?? 'document';
  }

  IconData _getIconForFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (['jpg', 'png', 'jpeg'].contains(ext)) return Icons.image;
    if (['mp4', 'mov', 'avi'].contains(ext)) return Icons.videocam;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['mp3', 'wav'].contains(ext)) return Icons.music_note;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isUploadingBatch,
      onPopInvoked: (didPop) {
        if (!didPop && isUploadingBatch) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("⚠️ Uploading in progress. Please wait.")),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const BackButton(color: Colors.black),
          title: const Text("Upload Files", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          centerTitle: true,
          actions: [
            if (uploadQueue.isNotEmpty && !isUploadingBatch)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: AppColors.blue),
                onPressed: pickFiles,
              )
          ],
        ),
        body: Stack(
          children: [
            Positioned(
              top: -100, right: -50,
              child: CircleAvatar(radius: 150, backgroundColor: AppColors.blue.withOpacity(0.15)),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text("Uploading to: ", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        Text(folderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (uploadQueue.isEmpty)
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          onTap: pickFiles,
                          child: Container(
                            height: 220,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppColors.blue.withOpacity(0.3), width: 2),
                              boxShadow: [BoxShadow(color: AppColors.blue.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 40,
                                  backgroundColor: AppColors.blue.withOpacity(0.1),
                                  child: const Icon(Icons.cloud_upload_rounded, size: 40, color: AppColors.blue),
                                ),
                                const SizedBox(height: 16),
                                const Text("Tap to select files", 
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)
                                ),
                                const SizedBox(height: 4),
                                Text("Select multiple images, videos, or docs", style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  else 
                    Expanded(
                      child: ListView.separated(
                        itemCount: uploadQueue.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = uploadQueue[index];
                          return _buildUploadTile(item);
                        },
                      ),
                    ),

                  if (uploadQueue.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    (() {
                      // ✅ ACCOUNT FOR 'EXISTS' STATUS IN DONE LOGIC
                      final allDone = uploadQueue.every((item) => item.status == 'done' || item.status == 'exists');
                      
                      return SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: isUploadingBatch 
                              ? null 
                              : (allDone ? () => Navigator.pop(context, true) : startBatchUpload),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: allDone ? Colors.green : AppColors.blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isUploadingBatch 
                              ? const Text("Processing Queue...", style: TextStyle(fontWeight: FontWeight.bold))
                              : Text(
                                  allDone 
                                    ? "Done" 
                                    : "Upload ${uploadQueue.where((item) => item.status == 'waiting' || item.status == 'error').length} Files",
                                   style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                                ),
                        ),
                      );
                    }()),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadTile(UploadItem item) {
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.circle_outlined;
    String statusText = "Waiting...";

    if (item.status == 'uploading') {
      statusColor = AppColors.blue;
      statusIcon = Icons.upload;
      statusText = "Uploading...";
    } else if (item.status == 'done') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = "Completed";
    } else if (item.status == 'exists') {
      // ✅ PROFESSIONAL DUPLICATE STYLE
      statusColor = Colors.orange; 
      statusIcon = Icons.cloud_done_outlined;
      statusText = "Already exists in cloud";
    } else if (item.status == 'error') {
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
      statusText = "Failed";
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getIconForFile(item.file.path), color: AppColors.blue, size: 24),
          ),
          const SizedBox(width: 12),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.file.path.split(Platform.pathSeparator).last,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (item.status == 'uploading')
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 4,
                      backgroundColor: Colors.grey[200],
                      color: AppColors.blue,
                    ),
                  )
                else
                  Text(
                    statusText,
                    style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
          
          const SizedBox(width: 12),
          
          if (item.status == 'waiting' && !isUploadingBatch)
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: Colors.grey),
              onPressed: () {
                setState(() {
                  uploadQueue.remove(item);
                });
              },
            )
          else
            Icon(statusIcon, color: statusColor, size: 22),
        ],
      ),
    );
  }
}