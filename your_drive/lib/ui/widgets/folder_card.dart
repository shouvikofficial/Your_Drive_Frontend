import 'package:flutter/material.dart';
import 'glass_card.dart';

class FolderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String info;
  final Color color;
  final VoidCallback onTap;
  
  // New Callbacks for Google Drive-like options
  final VoidCallback? onRename;
  final VoidCallback? onShare;
  final VoidCallback? onStar;
  final VoidCallback? onDelete;

  const FolderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.info,
    required this.color,
    required this.onTap,
    this.onRename,
    this.onShare,
    this.onStar,
    this.onDelete,
  });

  /// Opens a Google Drive-style Bottom Sheet menu
  void _showActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Wrap content
              children: [
                // Header: Shows folder details in the menu
                ListTile(
                  leading: Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: color, size: 22),
                  ),
                  title: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    info,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ),
                ),
                Divider(color: Colors.grey.withOpacity(0.2)),

                // Menu Options
                _buildMenuOption(
                  context,
                  icon: Icons.person_add_alt_1_rounded,
                  label: "Share",
                  onTap: onShare,
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.star_border_rounded,
                  label: "Add to Starred",
                  onTap: onStar,
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.edit_rounded,
                  label: "Rename",
                  onTap: onRename,
                ),
                _buildMenuOption(
                  context,
                  icon: Icons.delete_rounded,
                  label: "Delete",
                  onTap: onDelete,
                  isDestructive: true, // Makes it red
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Helper widget to keep menu options clean and consistent
  Widget _buildMenuOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final textColor = isDestructive ? Colors.redAccent : Colors.black87;
    final iconColor = isDestructive ? Colors.redAccent : Colors.black54;

    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      onTap: () {
        Navigator.pop(context); // Close the bottom sheet
        if (onTap != null) onTap(); // Execute the action
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showActionMenu(context), // Triggers menu on hold
      child: GlassCard(
        child: Stack(
          children: [
            /// 1. MAIN CONTENT (Compact & Clean - Untouched)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    info,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.black.withOpacity(0.45),
                    ),
                  ),
                ],
              ),
            ),

            /// 2. 3-DOT MENU (Minimalist Top Right)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () => _showActionMenu(context), // Triggers menu on tap
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(
                      Icons.more_horiz_rounded,
                      color: Colors.black.withOpacity(0.3),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}