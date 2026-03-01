import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class QuickActionsRow extends StatelessWidget {
  final VoidCallback onUpload;
  final VoidCallback onCreateFolder;
  final VoidCallback onBackup;
  final VoidCallback onShare;

  const QuickActionsRow({
    super.key,
    required this.onUpload,
    required this.onCreateFolder,
    required this.onBackup,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        QuickActionButton(
          icon: Icons.cloud_upload_rounded,
          label: 'Upload',
          gradient: AppColors.gradientBlue,
          onTap: onUpload,
        ),
        QuickActionButton(
          icon: Icons.create_new_folder_rounded,
          label: 'Folder',
          gradient: AppColors.gradientGreen,
          onTap: onCreateFolder,
        ),
        QuickActionButton(
          icon: Icons.backup_rounded,
          label: 'Backup',
          gradient: AppColors.gradientPurple,
          onTap: onBackup,
        ),
        QuickActionButton(
          icon: Icons.share_rounded,
          label: 'Share',
          gradient: AppColors.gradientPink,
          onTap: onShare,
        ),
      ],
    );
  }
}
