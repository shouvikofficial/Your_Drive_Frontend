import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/upload_manager.dart';
import '../../theme/app_colors.dart';
import 'glass_card.dart';
import 'upload_location_sheet.dart';
import '../upload_page.dart';

class BottomNavBar extends StatelessWidget {
  final VoidCallback onHome;
  final VoidCallback onCreateFolder;
  final VoidCallback onFiles;
  final VoidCallback onProfile;
  final VoidCallback onNotifications;
  final int unreadCount;

  /// 👇 NEW: active tab index for highlight
  final int selectedIndex;

  const BottomNavBar({
    super.key,
    required this.onHome,
    required this.onCreateFolder,
    required this.onFiles,
    required this.onProfile,
    required this.onNotifications,
    required this.unreadCount,
    this.selectedIndex = 0,
  });

  // ============================================================
  // ➕ ADD OPTIONS SHEET (Google Drive-style)
  // ============================================================
  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddOptionsSheet(
        onCreateFolder: onCreateFolder,
      ),
    );
  }

  // ============================================================
  // 🔹 NAV ITEM BUILDER
  // ============================================================
  Widget _navItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required VoidCallback onTap,
    required bool active,
    Widget? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? AppColors.blue.withOpacity(0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    active ? activeIcon : icon,
                    size: 22,
                    color: active ? AppColors.blue : Colors.grey[500],
                  ),
                ),
                if (badge != null) badge,
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.blue : Colors.grey[500],
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPad > 0 ? bottomPad : 12),
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
          BoxShadow(
            color: AppColors.blue.withOpacity(0.04),
            blurRadius: 40,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _navItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: 'Home',
            onTap: onHome,
            active: selectedIndex == 0,
          ),
          _navItem(
            icon: Icons.folder_outlined,
            activeIcon: Icons.folder_rounded,
            label: 'Files',
            onTap: onFiles,
            active: selectedIndex == 1,
          ),

          // ================= FAB =================
          GestureDetector(
            onTap: () => _showAddOptions(context),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.blue, AppColors.purple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.blue.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
          ),

          // ================= NOTIFICATION =================
          _navItem(
            icon: Icons.notifications_outlined,
            activeIcon: Icons.notifications_rounded,
            label: 'Alerts',
            onTap: onNotifications,
            active: selectedIndex == 2,
            badge: unreadCount > 0
                ? Positioned(
                    right: 2,
                    top: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF3B30).withOpacity(0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  )
                : null,
          ),

          _navItem(
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded,
            label: 'Profile',
            onTap: onProfile,
            active: selectedIndex == 3,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 🆕 Google Drive-style "Create new" Bottom Sheet
// ============================================================
class _AddOptionsSheet extends StatelessWidget {
  final VoidCallback onCreateFolder;

  const _AddOptionsSheet({required this.onCreateFolder});

  Future<void> _captureAndUpload(
    BuildContext context,
    ImageSource source,
    CameraDevice camera,
  ) async {
    Navigator.pop(context);

    final picker = ImagePicker();
    final XFile? file;

    if (source == ImageSource.camera) {
      file = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: camera,
        imageQuality: 95,
      );
    } else {
      file = await picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: camera,
        maxDuration: const Duration(minutes: 30),
      );
    }

    if (file == null) return;

    final manager = UploadManager();
    final nativeFile = File(file.path);

    final item = await manager.addNativeFile(
      file: nativeFile,
      folderId: null,
      folderName: 'My Drive',
    );

    if (!manager.isUploading) {
      manager.startBatchUpload();
    } else {
      manager.uploadAdditionalItems([item]);
    }

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const UploadPage(folderId: null),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),

          // ── Handle bar ──
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[350],
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          const SizedBox(height: 18),

          // ── Title (matches dashboard header style) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Text(
                  'Create new',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Options Grid (dashboard CategoryCard style) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Row 1: Folder + Upload
                Row(
                  children: [
                    Expanded(
                      child: _DashboardOptionCard(
                        icon: Icons.create_new_folder_rounded,
                        title: 'Folder',
                        subtitle: 'Create new',
                        color: AppColors.green,
                        onTap: () {
                          Navigator.pop(context);
                          onCreateFolder();
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _DashboardOptionCard(
                        icon: Icons.cloud_upload_rounded,
                        title: 'Upload',
                        subtitle: 'From device',
                        color: AppColors.blue,
                        onTap: () {
                          Navigator.pop(context);
                          showUploadLocationPicker(context);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Row 2: Camera Photo + Record Video
                Row(
                  children: [
                    Expanded(
                      child: _DashboardOptionCard(
                        icon: Icons.camera_alt_rounded,
                        title: 'Photo',
                        subtitle: 'Take a photo',
                        color: AppColors.orange,
                        onTap: () => _captureAndUpload(
                          context,
                          ImageSource.camera,
                          CameraDevice.rear,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _DashboardOptionCard(
                        icon: Icons.videocam_rounded,
                        title: 'Video',
                        subtitle: 'Record video',
                        color: AppColors.purple,
                        onTap: () {
                          Navigator.pop(context);
                          _recordVideo(context);
                        },
                      ),
                    ),
                  ],
                ),

              ],
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }

  void _recordVideo(BuildContext context) async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxDuration: const Duration(minutes: 30),
    );

    if (file == null) return;

    final manager = UploadManager();
    final nativeFile = File(file.path);

    final item = await manager.addNativeFile(
      file: nativeFile,
      folderId: null,
      folderName: 'My Drive',
    );

    if (!manager.isUploading) {
      manager.startBatchUpload();
    } else {
      manager.uploadAdditionalItems([item]);
    }

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const UploadPage(folderId: null),
        ),
      );
    }
  }
}

// ============================================================
// 🔷 Dashboard-style Option Card (matches CategoryCard / GlassCard)
// ============================================================
class _DashboardOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _DashboardOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withOpacity(0.2),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}