import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/saf_service.dart';

import '../theme/app_colors.dart';
import '../services/upload_manager.dart';

class UploadPage extends StatefulWidget {
  final String? folderId;
  const UploadPage({super.key, this.folderId});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final manager = UploadManager(); 
  String folderName = "My Drive";
  bool _isPreparing = false; 

  @override
  void initState() {
    super.initState();
    if (manager.currentFolderName != "My Drive") {
      folderName = manager.currentFolderName;
    }
    if (manager.uploadQueue.isEmpty) {
      manager.restoreQueue();
    }
  }

  Future<void> pickFiles() async {
    final files = await SafService.pickFiles();
    if (files == null || files.isEmpty) return;

    setState(() => _isPreparing = true);
    await Future.delayed(const Duration(milliseconds: 200));

    final newItems = <UploadItem>[];
    for (final file in files) {
      final item = await manager.addSafFile(
        uri: file['uri'],
        name: file['name'],
        size: file['size'],
        folderId: widget.folderId,
        folderName: folderName,
      );
      if (item != null) newItems.add(item);
    }

    if (mounted) {
      setState(() => _isPreparing = false);
    }

    if (newItems.isNotEmpty) {
      if (manager.isUploading) {
        manager.uploadAdditionalItems(newItems);
      } else {
        manager.startBatchUpload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isPreparing,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const BackButton(color: Colors.black87),
          title: const Text(
            "Upload Files", 
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)
          ),
          centerTitle: true,
          actions: [
            ListenableBuilder(
              listenable: manager,
              builder: (context, _) {
                if (manager.uploadQueue.isNotEmpty && !_isPreparing) {
                  return IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.blue, size: 26),
                    onPressed: pickFiles,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            // Decorative background
            Positioned(
              top: -80, right: -40,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.blue.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              bottom: 100, left: -60,
              child: Container(
                width: 150, height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.purple.withOpacity(0.05),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              child: Column(
                children: [
                  // Folder Info Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_shared, size: 18, color: AppColors.blue.withOpacity(0.8)),
                        const SizedBox(width: 10),
                        Text("Uploading to: ", style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(manager.currentFolderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  ListenableBuilder(
                    listenable: manager,
                    builder: (context, _) {
                      if (_isPreparing) {
                        return const Spacer();
                      }
                      if (manager.uploadQueue.isEmpty) {
                        return _buildEmptyState();
                      }
                      return Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView.separated(
                                itemCount: manager.uploadQueue.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                addAutomaticKeepAlives: false,
                                addRepaintBoundaries: true,
                                padding: const EdgeInsets.only(bottom: 20),
                                itemBuilder: (context, index) {
                                  final item = manager.uploadQueue[index];
                                  return RepaintBoundary(
                                    key: ValueKey(item.id),
                                    child: _buildUploadTile(item),
                                  );
                                },
                              ),
                            ),
                            _buildActionButton(),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            if (_isPreparing)
              ListenableBuilder(
                listenable: manager,
                builder: (context, _) {
                  return Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black.withOpacity(0.2),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10))
                          ]
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(color: AppColors.blue, strokeWidth: 3.5),
                            const SizedBox(height: 24),
                            const Text(
                              "Preparing Files...",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Processed ${manager.filesProcessed} of ${manager.totalFilesToProcess}",
                              style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: pickFiles,
          child: Container(
            height: 240,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.blue.withOpacity(0.4), width: 2, strokeAlign: BorderSide.strokeAlignInside),
              boxShadow: [
                BoxShadow(color: AppColors.blue.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 12))
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_upload_rounded, size: 48, color: AppColors.blue),
                ),
                const SizedBox(height: 20),
                const Text("Tap to select files", 
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)
                ),
                const SizedBox(height: 8),
                Text("Images, videos, or documents", style: TextStyle(fontSize: 15, color: Colors.grey[500])),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final allDone = manager.uploadQueue.every((item) => 
      item.status == 'done' || item.status == 'exists' || item.status == 'cancelled'
    );
    final hasPaused = manager.uploadQueue.any((item) =>
      item.status == 'paused' || item.status == 'interrupted'
    );
    
    final int waitingCount = manager.uploadQueue.where((item) => 
      item.status == 'waiting' || item.status == 'error' || item.status == 'no_internet'
    ).length;

    final int pausedCount = manager.uploadQueue.where((item) => item.status == 'paused' || item.status == 'interrupted').length;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            if (!allDone) BoxShadow(color: (hasPaused ? Colors.orange : AppColors.blue).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: manager.isUploading 
              ? () => Navigator.pop(context) 
              : (allDone 
                  ? () {
                      manager.clearCompleted();
                      Navigator.pop(context);
                    } 
                  : hasPaused
                    ? manager.resumeAll
                    : manager.startBatchUpload),
          icon: Icon(
            allDone ? Icons.check_circle_outline : (hasPaused ? Icons.play_circle_filled_rounded : Icons.cloud_upload_rounded),
            size: 24,
          ),
          label: Text(
            manager.isUploading 
                ? "Run in Background"
                : allDone 
                  ? "Done" 
                  : hasPaused
                    ? "Resume $pausedCount Paused"
                    : "Upload $waitingCount Files",
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: allDone ? AppColors.green : (hasPaused ? Colors.orange : AppColors.blue),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ),
    );
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes == 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildUploadTile(UploadItem item) {
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.circle_outlined;
    String statusText = "Waiting";
    bool isActive = false; 

    final pathForIcon = item.file != null ? item.file!.path : (item.name ?? "file");
    final fileName = item.file != null
        ? item.file!.path.split(Platform.pathSeparator).last
        : item.name ?? "file";
    final sizeLabel = _formatSize(
      item.size ?? (item.file != null ? item.file!.lengthSync() : null),
    );

    switch (item.status) {
      case 'preparing':
        statusColor = Colors.blueGrey;
        statusIcon = Icons.hourglass_bottom_rounded;
        statusText = "Preparing";
        isActive = true;
        break;
      case 'encrypting':
        statusColor = const Color(0xFF00897B); 
        statusIcon = Icons.lock_outline_rounded;
        statusText = "Encrypting";
        isActive = true;
        break;
      case 'initializing':
        statusColor = Colors.indigo;
        statusIcon = Icons.settings_rounded;
        statusText = "Initializing";
        isActive = true;
        break;
      case 'uploading':
        statusColor = AppColors.blue;
        statusIcon = Icons.upload_rounded;
        statusText = "Uploading";
        isActive = true;
        break;
      case 'finalizing':
        statusColor = Colors.deepPurple;
        statusIcon = Icons.cloud_sync_rounded;
        statusText = "Finalizing";
        isActive = true;
        break;
      case 'done':
        statusColor = AppColors.green;
        statusIcon = Icons.check_circle_rounded;
        statusText = "Completed";
        break;
      case 'exists':
        statusColor = Colors.orange;
        statusIcon = Icons.cloud_done_outlined;
        statusText = "Already exists";
        break;
      case 'no_internet':
        statusColor = Colors.orange;
        statusIcon = Icons.wifi_off_rounded;
        statusText = "No Internet";
        break;
      case 'error':
        statusColor = Colors.redAccent;
        statusIcon = Icons.error_outline_rounded;
        statusText = "Failed";
        break;
      case 'cancelled':
        statusColor = Colors.redAccent;
        statusIcon = Icons.cancel_rounded;
        statusText = "Cancelled";
        break;
      case 'paused':
      case 'interrupted':
        statusColor = Colors.orange;
        statusIcon = Icons.pause_circle_filled_rounded;
        statusText = "Paused";
        break;
    }

    final bool isUploading = item.status == 'uploading';
    final int pct = (item.progress * 100).round();
    final bool showProgressBar = isUploading || (['paused', 'interrupted'].contains(item.status) && item.progress > 0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          // File Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_getIconForFile(pathForIcon), color: statusColor, size: 28),
          ),
          const SizedBox(width: 16),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                Row(
                  children: [
                    if (isActive)
                      SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: statusColor),
                      )
                    else
                      Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 6),

                    Text(
                      isUploading 
                          ? 'Uploading · $pct%' 
                          : (['paused', 'interrupted'].contains(item.status) && pct > 0)
                            ? 'Paused · $pct%'
                            : statusText,
                      style: TextStyle(fontSize: 13, color: statusColor, fontWeight: FontWeight.w600),
                    ),

                    if (sizeLabel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 4, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[400], shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          sizeLabel,
                          style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),

                // SMOOTH Progress Bar
                if (showProgressBar) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.0, end: item.progress),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: Colors.grey[200],
                          color: (['paused', 'interrupted'].contains(item.status)) ? Colors.orange : AppColors.blue,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Actions
          if (isUploading)
            Container(
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.close_rounded, size: 20, color: Colors.red[400]),
                onPressed: () => manager.cancelUpload(item),
              ),
            )
          else if ((item.status == 'waiting' || item.status == 'paused' || item.status == 'interrupted') && !manager.isUploading)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 24, color: Colors.black38),
              onPressed: () => manager.removeFile(item),
            )
          else if (item.status == 'done')
            Icon(Icons.check_circle_rounded, color: AppColors.green.withOpacity(0.5), size: 32)
        ],
      ),
    );
  }

  IconData _getIconForFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (['jpg', 'png', 'jpeg', 'webp', 'heic'].contains(ext)) return Icons.image_rounded;
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return Icons.videocam_rounded;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf_rounded; 
    if (['mp3', 'wav', 'aac', 'm4a'].contains(ext)) return Icons.music_note_rounded;
    if (['doc', 'docx'].contains(ext)) return Icons.description_rounded;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart_rounded;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip_rounded;
    return Icons.insert_drive_file_rounded;
  }
}
