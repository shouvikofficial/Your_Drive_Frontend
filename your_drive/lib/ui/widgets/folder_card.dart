import 'package:flutter/material.dart';
import 'glass_card.dart';

class FolderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String info;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  const FolderCard({
    super.key,
    required this.icon,
    required this.title,
    required this.info,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassCard(
        child: Stack(
          children: [
            /// 1. MAIN CONTENT (Compact & Clean)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12), // Balanced padding
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Folder Icon (Smaller & Sleeker)
                  Container(
                    height: 36, // Reduced size
                    width: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1), // Very subtle background
                      borderRadius: BorderRadius.circular(10), // Soft square look
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: color, size: 20),
                  ),
                  
                  const Spacer(), // Pushes text to bottom naturally
                  
                  // Folder Name
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14, // Perfect size for cards
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      letterSpacing: 0.2,
                    ),
                  ),
                  
                  const SizedBox(height: 3), // Tiny gap
                  
                  // Subtitle (Tap to open)
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
                child: SizedBox(
                  width: 30, // Restrict touch area so it doesn't overlap text
                  height: 30,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_horiz_rounded, // Horizontal dots look cleaner
                      color: Colors.black.withOpacity(0.3), 
                      size: 20
                    ),
                    elevation: 3,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (value) {
                      if (value == 'delete' && onDelete != null) {
                        onDelete!();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'delete',
                        height: 38,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFECEC),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 16),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              "Delete",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
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
  }
}