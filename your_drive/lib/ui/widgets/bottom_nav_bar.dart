import 'dart:ui';
import 'package:flutter/material.dart';
import 'add_options.dart';

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
  // ➕ ADD OPTIONS SHEET
  // ============================================================
  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetItem(
                icon: Icons.upload_file,
                color: Colors.blue,
                title: "Upload file",
                onTap: () {
                  Navigator.pop(context);
                  showUploadLocationPicker(context);
                },
              ),
              _sheetItem(
                icon: Icons.create_new_folder,
                color: Colors.green,
                title: "Create folder",
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

  Widget _sheetItem({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      onTap: onTap,
    );
  }

  // ============================================================
  // 🔹 NAV ICON BUILDER
  // ============================================================
  Widget _navIcon({
    required IconData icon,
    required VoidCallback onTap,
    required bool active,
    Widget? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: active ? Colors.blue.withOpacity(0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 24,
              color: active ? Colors.blue : Colors.black87,
            ),
          ),
          if (badge != null) badge,
        ],
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.65),
                    Colors.white.withOpacity(0.35),
                  ],
                ),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navIcon(
                    icon: Icons.home_rounded,
                    onTap: onHome,
                    active: selectedIndex == 0,
                  ),
                  _navIcon(
                    icon: Icons.folder_rounded,
                    onTap: onFiles,
                    active: selectedIndex == 1,
                  ),

                  // ================= FAB =================
                  GestureDetector(
                    onTap: () => _showAddOptions(context),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F8CFF), Color(0xFF6A5BFF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F8CFF).withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 30),
                    ),
                  ),

                  // ================= NOTIFICATION =================
                  _navIcon(
                    icon: Icons.notifications_rounded,
                    onTap: onNotifications,
                    active: selectedIndex == 2,
                    badge: unreadCount > 0
                        ? Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Text(
                                unreadCount > 9 ? '9+' : unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),

                  _navIcon(
                    icon: Icons.person_rounded,
                    onTap: onProfile,
                    active: selectedIndex == 3,
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
