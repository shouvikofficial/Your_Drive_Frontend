import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../theme/app_colors.dart';
import '../services/upload_manager.dart'; // ✅ Import the manager

class UploadPage extends StatefulWidget {
  final String? folderId;
  const UploadPage({super.key, this.folderId});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  // ✅ Get the Global Singleton Instance
  final manager = UploadManager(); 
  
  // Local state for initial folder name setup (UI only)
  String folderName = "My Drive";
  
  // ✅ THE TRICK: Local state for heavy processing
  bool _isPreparing = false; 

  @override
  void initState() {
    super.initState();
    if (manager.currentFolderName != "My Drive") {
      folderName = manager.currentFolderName;
    }
  }

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true, 
      withData: false,
    );
    
    if (result != null) {
      // ✅ Step 1: Show "Preparing" UI immediately
      setState(() => _isPreparing = true);

      // ✅ Step 2: Give the UI a moment to render the spinner 
      // before the CPU gets busy with file objects.
      await Future.delayed(const Duration(milliseconds: 300));

      final files = result.paths
          .where((p) => p != null)
          .map((p) => File(p!))
          .toList();
      
      // ✅ Step 3: Add files to the Global Manager (now async)
      await manager.addFiles(files, widget.folderId, folderName);

      // ✅ Step 4: Hide "Preparing" UI
      if (mounted) {
        setState(() => _isPreparing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: manager,
      builder: (context, child) {
        return PopScope(
          // Prevent back button while preparing data to avoid crashes
          canPop: !_isPreparing, 
          child: Scaffold(
            backgroundColor: AppColors.bg,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: const BackButton(color: Colors.black),
              title: const Text("Upload Files", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              centerTitle: true,
              actions: [
                // Disable add button while preparing
                if (!manager.isUploading && manager.uploadQueue.isNotEmpty && !_isPreparing)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.blue),
                    onPressed: pickFiles,
                  )
              ],
            ),
            body: Stack(
              children: [
                // Background decoration
                Positioned(
                  top: -100, right: -50,
                  child: CircleAvatar(radius: 150, backgroundColor: AppColors.blue.withOpacity(0.15)),
                ),

                // Main Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      // 📂 Folder Info Badge
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
                            Text(manager.currentFolderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 📋 Empty State or List
                      if (manager.uploadQueue.isEmpty && !_isPreparing)
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
                      else if (!_isPreparing)
                        Expanded(
                          child: ListView.separated(
                            itemCount: manager.uploadQueue.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final item = manager.uploadQueue[index];
                              return _buildUploadTile(item);
                            },
                          ),
                        )
                      else 
                        const Spacer(), // Keeps layout consistent during preparation

                      // 🚀 Action Button
                      if (manager.uploadQueue.isNotEmpty && !_isPreparing) ...[
                        const SizedBox(height: 16),
                        (() {
                          final allDone = manager.uploadQueue.every((item) => 
                            item.status == 'done' || item.status == 'exists' || item.status == 'cancelled'
                          );
                          
                          return SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: manager.isUploading 
                                  ? () => Navigator.pop(context) 
                                  : (allDone 
                                      ? () {
                                          manager.clearCompleted();
                                          Navigator.pop(context);
                                        } 
                                      : manager.startBatchUpload),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: allDone ? Colors.green : AppColors.blue,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: manager.isUploading 
                                  ? const Text("Uploading...", style: TextStyle(fontWeight: FontWeight.bold))
                                  : Text(
                                      allDone 
                                        ? "Done" 
                                        : "Upload ${manager.uploadQueue.where((item) => item.status == 'waiting' || item.status == 'error').length} Files",
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                                    ),
                            ),
                          );
                        }()),
                      ],
                    ],
                  ),
                ),

                // ✅ THE PREPARING OVERLAY (Shows on top of everything)
                if (_isPreparing)
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black.withOpacity(0.05), // Subtle dimming
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
                          ]
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: AppColors.blue, strokeWidth: 3),
                            const SizedBox(height: 20),
                            const Text(
                              "Preparing your data...",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                            ),
                            const SizedBox(height: 8),
                            // Show the file counter from the manager
                            Text(
                              "Processing: ${manager.filesProcessed} of ${manager.totalFilesToProcess}",
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUploadTile(UploadItem item) {
    Color statusColor = Colors.grey;
IconData statusIcon = Icons.circle_outlined;
String statusText = "Waiting...";

switch (item.status) {
  case 'preparing':
    statusColor = Colors.blueGrey;
    statusIcon = Icons.hourglass_bottom;
    statusText = "Preparing...";
    break;

  case 'initializing':
    statusColor = Colors.indigo;
    statusIcon = Icons.settings;
    statusText = "Initializing...";
    break;

  case 'uploading':
    statusColor = AppColors.blue;
    statusIcon = Icons.upload;
    statusText = "Uploading...";
    break;

  case 'finalizing':
    statusColor = Colors.deepPurple;
    statusIcon = Icons.cloud_done;
    statusText = "Finalizing...";
    break;

  case 'done':
    statusColor = Colors.green;
    statusIcon = Icons.check_circle;
    statusText = "Completed";
    break;

  case 'exists':
    statusColor = Colors.orange;
    statusIcon = Icons.cloud_done_outlined;
    statusText = "Already exists in cloud";
    break;

  case 'error':
    statusColor = Colors.red;
    statusIcon = Icons.error_outline;
    statusText = "Failed";
    break;

  case 'cancelled':
    statusColor = Colors.redAccent;
    statusIcon = Icons.block;
    statusText = "Cancelled";
    break;
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
          if (item.status == 'uploading')
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.cancel, size: 22, color: Colors.redAccent),
              onPressed: () => manager.cancelUpload(item),
            )
          else if (item.status == 'waiting' && !manager.isUploading)
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.close, size: 20, color: Colors.grey),
              onPressed: () => manager.removeFile(item),
            )
          else
            Icon(statusIcon, color: statusColor, size: 22),
        ],
      ),
    );
  }

  IconData _getIconForFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (['jpg', 'png', 'jpeg', 'webp', 'heic'].contains(ext)) return Icons.image;
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return Icons.videocam;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf; 
    if (['mp3', 'wav', 'aac'].contains(ext)) return Icons.music_note;
    if (['doc', 'docx'].contains(ext)) return Icons.description;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart;
    return Icons.insert_drive_file;
  }
}