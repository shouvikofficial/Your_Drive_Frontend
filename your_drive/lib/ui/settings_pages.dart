import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../services/biometric_service.dart'; 
import '../services/backup_service.dart';
import 'devices_sessions_page.dart';

/// ------------------------------------------------------
/// ☁️ BACKUP & SYNC PAGE (With Instant Triggers)
/// ------------------------------------------------------
class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  bool _backupEnabled = false;
  bool _wifiOnly = true;
  bool _chargingOnly = false;
  
  // Instance to trigger logic instantly
  final BackupService _backupService = BackupService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _backupEnabled = prefs.getBool('backup_enabled') ?? false;
        _wifiOnly = prefs.getBool('wifi_only') ?? true;
        _chargingOnly = prefs.getBool('charging_only') ?? false;
      });
    }
  }

  /// ⚡ MAIN TOGGLE (Start/Stop)
  Future<void> _toggleBackup(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('backup_enabled', value);
    setState(() => _backupEnabled = value);

    if (value) {
      // 🚀 INSTANT START
      _backupService.initBackgroundService();
      _backupService.startAutoBackup();
      _backupService.scheduleBackgroundBackup();
    } else {
      // 🛑 INSTANT STOP
      _backupService.stopBackup();
      _backupService.cancelBackgroundBackup();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Backup & Sync", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ☁️ MAIN CARD
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.blue.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                const Icon(Icons.cloud_upload_rounded, size: 48, color: AppColors.blue),
                const SizedBox(height: 12),
                const Text("Automatic Backup", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text("Keep your photos & videos safe", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                Switch(
                  value: _backupEnabled,
                  activeColor: AppColors.blue,
                  onChanged: _toggleBackup,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          const SectionHeader(title: "Preferences"),
          
          // 📶 WI-FI ONLY (Instant Trigger)
          SettingsTile(
            icon: Icons.wifi,
            title: "Back up over Wi-Fi only",
            subtitle: "Save mobile data usage",
            trailing: Switch(
              value: _wifiOnly,
              activeColor: AppColors.blue,
              onChanged: _backupEnabled ? (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('wifi_only', val);
                setState(() => _wifiOnly = val);
                
                // ⚡ FIRE INSTANTLY: Re-runs logic to Pause/Resume based on new setting
                _backupService.startAutoBackup(); 
              } : null,
            ),
          ),

          // 🔋 CHARGING ONLY (Instant Trigger)
          SettingsTile(
            icon: Icons.battery_charging_full,
            title: "Back up while charging only",
            subtitle: "Save battery life",
            trailing: Switch(
              value: _chargingOnly,
              activeColor: AppColors.blue,
              onChanged: _backupEnabled ? (val) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('charging_only', val);
                setState(() => _chargingOnly = val);
                
                // ⚡ FIRE INSTANTLY
                _backupService.startAutoBackup();
              } : null,
            ),
          ),

          // 📊 LIVE STATUS INDICATOR (Phase + Text)
          const SizedBox(height: 24),
          ValueListenableBuilder<BackupPhase>(
            valueListenable: _backupService.phaseNotifier,
            builder: (context, phase, _) {
              return ValueListenableBuilder<String>(
                valueListenable: _backupService.statusNotifier,
                builder: (context, status, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _phaseColor(phase).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        _phaseIcon(phase),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            status,
                            style: TextStyle(
                              color: _phaseColor(phase),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),

          // Progress bar
          ValueListenableBuilder<double>(
            valueListenable: _backupService.progressNotifier,
            builder: (context, progress, _) {
              if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                    color: AppColors.blue,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _phaseColor(BackupPhase phase) {
    switch (phase) {
      case BackupPhase.uploading:
      case BackupPhase.scanning:
        return AppColors.blue;
      case BackupPhase.complete:
        return Colors.green;
      case BackupPhase.error:
        return Colors.red;
      case BackupPhase.waitingWifi:
      case BackupPhase.waitingCharger:
        return Colors.orange;
      case BackupPhase.idle:
        return Colors.grey;
    }
  }

  Widget _phaseIcon(BackupPhase phase) {
    switch (phase) {
      case BackupPhase.uploading:
        return const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
        );
      case BackupPhase.scanning:
        return const Icon(Icons.search, size: 18, color: Colors.blue);
      case BackupPhase.complete:
        return const Icon(Icons.check_circle, size: 18, color: Colors.green);
      case BackupPhase.error:
        return const Icon(Icons.error, size: 18, color: Colors.red);
      case BackupPhase.waitingWifi:
        return const Icon(Icons.wifi_off, size: 18, color: Colors.orange);
      case BackupPhase.waitingCharger:
        return const Icon(Icons.battery_alert, size: 18, color: Colors.orange);
      case BackupPhase.idle:
        return const Icon(Icons.cloud_done, size: 18, color: Colors.grey);
    }
  }
}

/// ------------------------------------------------------
/// 🔒 PRIVACY & SECURITY PAGE
/// ------------------------------------------------------
class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  bool _biometricEnabled = false;
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      bool authenticated = await BiometricService.authenticate();
      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('biometric_enabled', true);
        setState(() => _biometricEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Biometric unlock enabled"), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Authentication failed"), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometric_enabled', false);
      setState(() => _biometricEnabled = false);
    }
  }

  /// 🗑️ Clear cached thumbnails, previews, temp files
  Future<void> _clearCacheData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Clear Cache & Data"),
        content: const Text(
          "This will remove cached thumbnails, previews, and temporary files. "
          "Your uploaded files in the cloud will not be affected.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Clear"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _clearingCache = true);

    try {
      // Clear app cache directory
      final cacheDir = await getTemporaryDirectory();
      if (cacheDir.existsSync()) {
        await for (final entity in cacheDir.list()) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (_) {}
        }
      }

      // Clear app-specific temp directories
      final appDir = await getApplicationDocumentsDirectory();
      final thumbDir = Directory('${appDir.path}/thumbnails');
      final previewDir = Directory('${appDir.path}/previews');
      for (final dir in [thumbDir, previewDir]) {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }

      // Clear search history from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('search_history');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cache cleared successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to clear cache: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  /// 🗑️ DELETE ACCOUNT
  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("Delete Account"),
          ],
        ),
        content: const Text(
          "This action is irreversible. All your files, backups, and personal data will be permanently deleted."
          "\n\nAre you absolutely sure?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete Forever"),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // TODO: Implement actual account deletion via Supabase
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Account deletion request submitted"),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Privacy & Security", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionHeader(title: "Security"),

          SettingsTile(
            icon: Icons.fingerprint,
            title: "Biometric Unlock",
            subtitle: "Use fingerprint to open app",
            trailing: Switch(
              value: _biometricEnabled,
              activeColor: AppColors.blue,
              onChanged: _toggleBiometric,
            ),
          ),

          /// ⭐ DEVICES & SESSIONS
          SettingsTile(
            icon: Icons.devices_outlined,
            title: "Devices & Sessions",
            subtitle: "Manage logged-in devices",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DevicesSessionsPage()),
            ),
          ),

          const SizedBox(height: 24),
          const SectionHeader(title: "Data"),

          SettingsTile(
            icon: Icons.cached_rounded,
            title: "Clear Cache",
            subtitle: "Remove thumbnails & temporary files",
            trailing: _clearingCache
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: _clearingCache ? null : _clearCacheData,
          ),

          const SizedBox(height: 24),
          const SectionHeader(title: "Danger Zone"),

          SettingsTile(
            icon: Icons.delete_forever,
            title: "Delete Account",
            subtitle: "Permanently remove your account & data",
            textColor: Colors.red,
            iconColor: Colors.red,
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }
}


/// ------------------------------------------------------
/// ❓ HELP & SUPPORT PAGE
/// ------------------------------------------------------
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Help & Support", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionHeader(title: "Support"),
          SettingsTile(
            icon: Icons.help_outline,
            title: "FAQs",
            subtitle: "Find quick answers",
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FAQsPage())),
          ),
          SettingsTile(
            icon: Icons.chat_bubble_outline,
            title: "Contact Support",
            subtitle: "We usually reply within 24 hours",
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ContactSupportPage())),
          ),

          const SizedBox(height: 24),
          const SectionHeader(title: "Legal"),
          SettingsTile(
            icon: Icons.description_outlined,
            title: "Terms of Service",
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TermsOfServicePage())),
          ),
          SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: "Privacy Policy",
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PrivacyPolicyPage())),
          ),

          const SizedBox(height: 40),

          /// 👨‍💻 DEVELOPER CREDIT
          const Center(
            child: Column(
              children: [
                Text(
                  "Developed by",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                SizedBox(height: 2),
                Text(
                  "Shouvik",
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          /// 📦 APP VERSION
          const Center(
            child: Text(
              "Version 1.0.0",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------
/// ❓ FAQs PAGE
/// ------------------------------------------------------
class FAQsPage extends StatelessWidget {
  const FAQsPage({super.key});

  static const List<Map<String, String>> _faqs = [
    {
      'q': 'What is Cloud Guard?',
      'a': 'Cloud Guard is a secure cloud storage application that lets you '
          'back up, organize, and access your files from anywhere. Your data '
          'is encrypted and stored safely so only you can access it.',
    },
    {
      'q': 'How do I upload files?',
      'a': 'Tap the "+" button on the home screen and choose "Upload File" '
          'or "Upload Folder". You can also enable automatic backup from '
          'Settings → Backup & Sync to keep your photos and documents '
          'synced automatically.',
    },
    {
      'q': 'Is my data encrypted?',
      'a': 'Yes. Cloud Guard uses end-to-end encryption. Files are encrypted '
          'on your device before they leave it, so no one — not even us — '
          'can read your data.',
    },
    {
      'q': 'How much storage do I get?',
      'a': 'Every Cloud Guard account comes with generous free storage. You '
          'can view your current usage on the Dashboard. If you need more '
          'space, upgrade options will be available in a future update.',
    },
    {
      'q': 'Can I access my files offline?',
      'a': 'Files you have recently opened are cached locally. For guaranteed '
          'offline access, use the "Make Available Offline" option on any '
          'file or folder.',
    },
    {
      'q': 'How do I recover deleted files?',
      'a': 'Deleted files are moved to Trash and kept for 30 days. Go to '
          'Trash from the side menu, select the file, and tap "Restore". '
          'After 30 days, files are permanently removed.',
    },
    {
      'q': 'What happens if I forget my password?',
      'a': 'Tap "Forgot Password" on the login screen. A reset link will be '
          'sent to your registered email address. Follow the instructions '
          'to set a new password.',
    },
    {
      'q': 'How do I enable automatic backup?',
      'a': 'Go to Settings → Backup & Sync → toggle "Auto Backup" on. '
          'You can choose to back up over Wi-Fi only or while charging '
          'to save battery and data.',
    },
    {
      'q': 'Can I share files with others?',
      'a': 'Yes. Long-press a file and choose "Share". You can generate a '
          'shareable link or send the file directly to another Cloud Guard '
          'user.',
    },
    {
      'q': 'How do I contact support?',
      'a': 'Go to Help & Support → Contact Support. You can email us or '
          'reach out via our social channels. We typically respond within '
          '24 hours.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("FAQs", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(
            color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.blue, AppColors.purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(Icons.quiz_rounded, color: Colors.white, size: 40),
                SizedBox(height: 10),
                Text(
                  "Frequently Asked Questions",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  "Everything you need to know about Cloud Guard",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // FAQ items
          ..._faqs.map((faq) => _FAQTile(
                question: faq['q']!,
                answer: faq['a']!,
              )),

          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ContactSupportPage())),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text("Still have questions? Contact us"),
              style: TextButton.styleFrom(foregroundColor: AppColors.blue),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _FAQTile extends StatefulWidget {
  final String question;
  final String answer;
  const _FAQTile({required this.question, required this.answer});

  @override
  State<_FAQTile> createState() => _FAQTileState();
}

class _FAQTileState extends State<_FAQTile>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: _expanded
            ? Border.all(color: AppColors.blue.withOpacity(0.3), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.help_outline_rounded,
                color: AppColors.blue, size: 20),
          ),
          title: Text(
            widget.question,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: _expanded ? AppColors.blue : Colors.black87,
            ),
          ),
          trailing: AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 250),
            child: Icon(Icons.keyboard_arrow_down_rounded,
                color: _expanded ? AppColors.blue : Colors.grey),
          ),
          onExpansionChanged: (val) => setState(() => _expanded = val),
          children: [
            Text(
              widget.answer,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------------------------------------------
/// 💬 CONTACT SUPPORT PAGE
/// ------------------------------------------------------
class ContactSupportPage extends StatelessWidget {
  const ContactSupportPage({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Contact Support",
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(
            color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.blue, AppColors.purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              children: [
                Icon(Icons.support_agent_rounded,
                    color: Colors.white, size: 48),
                SizedBox(height: 12),
                Text(
                  "We're here to help!",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 6),
                Text(
                  "Choose your preferred way to reach us.\nWe typically respond within 24 hours.",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          const SectionHeader(title: "Reach Out"),

          // Email
          _ContactTile(
            icon: Icons.email_outlined,
            iconColor: AppColors.blue,
            title: "Email Us",
            subtitle: "support@cloudguard.app",
            onTap: () => _launchUrl("mailto:support@cloudguard.app"
                "?subject=Cloud Guard Support Request"),
          ),

          // Twitter / X
          _ContactTile(
            icon: Icons.alternate_email_rounded,
            iconColor: const Color(0xFF1DA1F2),
            title: "Twitter / X",
            subtitle: "@CloudGuardApp",
            onTap: () => _launchUrl("https://twitter.com/CloudGuardApp"),
          ),

          // GitHub
          _ContactTile(
            icon: Icons.code_rounded,
            iconColor: Colors.black87,
            title: "GitHub",
            subtitle: "Report bugs & feature requests",
            onTap: () =>
                _launchUrl("https://github.com/CloudGuard/issues"),
          ),

          const SizedBox(height: 28),
          const SectionHeader(title: "Business Hours"),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                _InfoRow(label: "Mon – Fri", value: "9:00 AM – 6:00 PM IST"),
                const Divider(height: 24),
                _InfoRow(label: "Sat – Sun", value: "10:00 AM – 2:00 PM IST"),
                const Divider(height: 24),
                _InfoRow(label: "Email", value: "24 / 7 (async)"),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.black87)),
        subtitle: Text(subtitle,
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing:
            const Icon(Icons.open_in_new_rounded, size: 18, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Colors.black87)),
        Text(value, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
      ],
    );
  }
}

/// ------------------------------------------------------
/// 📝 TERMS OF SERVICE PAGE
/// ------------------------------------------------------
class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  static const String _lastUpdated = "March 1, 2026";

  static const List<Map<String, String>> _sections = [
    {
      'title': '1. Acceptance of Terms',
      'body': 'By downloading, installing, or using Cloud Guard ("the App"), '
          'you agree to be bound by these Terms of Service. If you do not '
          'agree, please do not use the App.',
    },
    {
      'title': '2. Description of Service',
      'body': 'Cloud Guard provides cloud-based file storage, backup, and '
          'synchronization services. We may update, modify, or discontinue '
          'features at our discretion with reasonable notice.',
    },
    {
      'title': '3. User Accounts',
      'body': 'You are responsible for maintaining the confidentiality of '
          'your account credentials. You agree to notify us immediately '
          'of any unauthorized access. Cloud Guard is not liable for '
          'losses caused by unauthorized use of your account.',
    },
    {
      'title': '4. Acceptable Use',
      'body': 'You agree not to use Cloud Guard to:\n'
          '• Upload or distribute illegal, harmful, or offensive content\n'
          '• Attempt to gain unauthorized access to our systems\n'
          '• Interfere with the proper functioning of the service\n'
          '• Violate any applicable laws or regulations',
    },
    {
      'title': '5. Intellectual Property',
      'body': 'All content, trademarks, and intellectual property within the '
          'App belong to Cloud Guard. You retain ownership of the files '
          'you upload. By using the App, you grant us a limited license '
          'to process your files solely to provide the service.',
    },
    {
      'title': '6. Data Storage & Limits',
      'body': 'Free accounts include a set storage quota. We reserve the '
          'right to modify storage limits with prior notice. Files '
          'in Trash are automatically deleted after 30 days.',
    },
    {
      'title': '7. Termination',
      'body': 'We may suspend or terminate your account if you violate these '
          'Terms. You may delete your account at any time from Settings. '
          'Upon termination, your data will be deleted within 30 days.',
    },
    {
      'title': '8. Limitation of Liability',
      'body': 'Cloud Guard is provided "as is." We are not liable for any '
          'indirect, incidental, or consequential damages arising from '
          'your use of the App, including data loss caused by factors '
          'beyond our reasonable control.',
    },
    {
      'title': '9. Changes to Terms',
      'body': 'We may revise these Terms from time to time. Continued use '
          'of Cloud Guard after changes constitutes acceptance of the '
          'updated Terms. We will notify users of material changes.',
    },
    {
      'title': '10. Contact',
      'body': 'For questions about these Terms, contact us at:\n'
          'support@cloudguard.app',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Terms of Service",
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(
            color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.blue, AppColors.purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.gavel_rounded, color: Colors.white, size: 36),
                const SizedBox(height: 10),
                const Text(
                  "Terms of Service",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  "Last updated: $_lastUpdated",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          // Sections
          ..._sections.map((s) => _LegalSection(
                title: s['title']!,
                body: s['body']!,
              )),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------
/// 🔐 PRIVACY POLICY PAGE
/// ------------------------------------------------------
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _lastUpdated = "March 1, 2026";

  static const List<Map<String, String>> _sections = [
    {
      'title': '1. Information We Collect',
      'body': 'Cloud Guard collects the following information:\n'
          '• Account details (name, email) during registration\n'
          '• Files and data you choose to upload\n'
          '• Device information (OS, app version) for diagnostics\n'
          '• Usage analytics (feature usage, crash reports)',
    },
    {
      'title': '2. How We Use Your Information',
      'body': 'We use your data to:\n'
          '• Provide and maintain the Cloud Guard service\n'
          '• Improve app performance and reliability\n'
          '• Send important service notifications\n'
          '• Respond to support requests\n\n'
          'We never sell your personal data to third parties.',
    },
    {
      'title': '3. Data Encryption & Security',
      'body': 'All files are encrypted using industry-standard encryption '
          'before being transmitted and stored. We use end-to-end '
          'encryption so your files are unreadable to anyone other than '
          'you — including Cloud Guard staff.',
    },
    {
      'title': '4. Data Storage',
      'body': 'Your encrypted files are stored on secure, geographically '
          'distributed servers. We implement strict access controls, '
          'regular security audits, and automated threat detection to '
          'protect your data.',
    },
    {
      'title': '5. Data Sharing',
      'body': 'We do not share your personal data except:\n'
          '• When required by law or valid legal process\n'
          '• With your explicit consent\n'
          '• With service providers who assist in operating our '
          'infrastructure (bound by confidentiality agreements)',
    },
    {
      'title': '6. Your Rights',
      'body': 'You have the right to:\n'
          '• Access and download your stored data at any time\n'
          '• Request correction of inaccurate personal information\n'
          '• Delete your account and all associated data\n'
          '• Opt out of non-essential communications',
    },
    {
      'title': '7. Data Retention',
      'body': 'We retain your data for as long as your account is active. '
          'Deleted files are purged within 30 days. Upon account deletion, '
          'all personal data is permanently removed within 30 days.',
    },
    {
      'title': '8. Children\'s Privacy',
      'body': 'Cloud Guard is not intended for children under 13. We do '
          'not knowingly collect data from children. If you believe a '
          'child has provided us with personal data, please contact us.',
    },
    {
      'title': '9. Changes to This Policy',
      'body': 'We may update this Privacy Policy periodically. Material '
          'changes will be communicated via in-app notification or email. '
          'Continued use after changes constitutes acceptance.',
    },
    {
      'title': '10. Contact Us',
      'body': 'For privacy-related inquiries, contact us at:\n'
          'privacy@cloudguard.app',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Privacy Policy",
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(
            color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.blue, AppColors.purple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.shield_rounded, color: Colors.white, size: 36),
                const SizedBox(height: 10),
                const Text(
                  "Privacy Policy",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  "Last updated: $_lastUpdated",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          // Commitment badge
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.green.withOpacity(0.2), width: 1),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_user_rounded,
                    color: AppColors.green, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Your Privacy Matters",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      SizedBox(height: 2),
                      Text(
                        "Cloud Guard is designed with privacy at its core. "
                        "We will never sell your data.",
                        style:
                            TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sections
          ..._sections.map((s) => _LegalSection(
                title: s['title']!,
                body: s['body']!,
              )),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// --- Shared helper for Terms / Privacy sections ---
class _LegalSection extends StatelessWidget {
  final String title;
  final String body;
  const _LegalSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87)),
          const SizedBox(height: 8),
          Text(body,
              style: TextStyle(
                  color: Colors.grey[700], fontSize: 13.5, height: 1.55)),
        ],
      ),
    );
  }
}


/// ------------------------------------------------------
/// 👤 ACCOUNT SETTINGS PAGE
/// ------------------------------------------------------
class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _isGoogleUser = false;
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final providers = user.appMetadata['providers'] as List<dynamic>? ?? [];
    final isGoogle = providers.contains('google');

    // Check encrypted_password directly via RPC (works across logins)
    bool hasPassword = false;
    try {
      final result = await Supabase.instance.client.rpc('has_password');
      hasPassword = result == true;
    } catch (_) {
      // Fallback: non-Google users always have a password
      hasPassword = !isGoogle;
    }

    if (mounted) {
      setState(() {
        _isGoogleUser = isGoogle && !hasPassword;
        _hasPassword = hasPassword;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Account Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionHeader(title: "Profile"),
          SettingsTile(
            icon: Icons.person_outline,
            title: "Edit Profile",
            subtitle: "Change your name & email",
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfilePage()),
              );
              _loadUserData(); // Refresh after editing
            },
          ),

          const SizedBox(height: 24),
          const SectionHeader(title: "Security"),

          if (_isGoogleUser && !_hasPassword)
            SettingsTile(
              icon: Icons.lock_outline,
              title: "Set Password",
              subtitle: "Create a password for email login",
              onTap: () => _showSetPasswordDialog(isNewPassword: true),
            )
          else
            SettingsTile(
              icon: Icons.lock_reset,
              title: "Change Password",
              subtitle: "Update your current password",
              onTap: () => _showChangePasswordDialog(),
            ),
        ],
      ),
    );
  }

  /// 🔑 SET PASSWORD (for Google-only users)
  Future<void> _showSetPasswordDialog({bool isNewPassword = false}) async {
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text(isNewPassword ? "Set Password" : "New Password"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isNewPassword
                    ? "Create a password so you can also sign in with your email."
                    : "Enter your new password.",
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPassCtrl,
                obscureText: obscure1,
                decoration: InputDecoration(
                  labelText: "New Password",
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure1 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setDialogState(() => obscure1 = !obscure1),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure2,
                decoration: InputDecoration(
                  labelText: "Confirm Password",
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure2 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setDialogState(() => obscure2 = !obscure2),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () async {
                final pw = newPassCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();
                if (pw.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Password must be at least 6 characters"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (pw != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Passwords do not match"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                try {
                  await Supabase.instance.client.auth
                      .updateUser(UserAttributes(password: pw));
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    setState(() => _hasPassword = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Password set successfully!"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } on AuthException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue),
              child: Text(isNewPassword ? "Set Password" : "Update"),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔑 CHANGE PASSWORD (for email users)
  Future<void> _showChangePasswordDialog() async {
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure1 = true;
    bool obscure2 = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text("Change Password"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Enter a new password for your account.",
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPassCtrl,
                obscureText: obscure1,
                decoration: InputDecoration(
                  labelText: "New Password",
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure1 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setDialogState(() => obscure1 = !obscure1),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure2,
                decoration: InputDecoration(
                  labelText: "Confirm Password",
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure2 ? Icons.visibility_off : Icons.visibility),
                    onPressed: () =>
                        setDialogState(() => obscure2 = !obscure2),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () async {
                final pw = newPassCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();
                if (pw.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Password must be at least 6 characters"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (pw != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Passwords do not match"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                try {
                  await Supabase.instance.client.auth
                      .updateUser(UserAttributes(password: pw));
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Password changed successfully!"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } on AuthException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue),
              child: const Text("Update Password"),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------------------------------------------
/// ✏️ EDIT PROFILE PAGE
/// ------------------------------------------------------
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _isGoogleUser = false;
  String _originalEmail = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final providers = user.appMetadata['providers'] as List<dynamic>? ?? [];
    final isGoogle = providers.contains('google') &&
        !providers.contains('email');

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('name, email')
        .eq('id', user.id)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _isGoogleUser = isGoogle;
        _nameCtrl.text = profile?['name'] ?? '';
        _emailCtrl.text = user.email ?? profile?['email'] ?? '';
        _originalEmail = _emailCtrl.text;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) throw 'Not logged in';

      final newName = _nameCtrl.text.trim();
      final newEmail = _emailCtrl.text.trim();

      // Update profile name in DB
      await supabase
          .from('profiles')
          .update({'name': newName, 'email': newEmail})
          .eq('id', user.id);

      // Update cached values
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', newName);
      await prefs.setString('user_email', newEmail);

      // If email changed, update Supabase auth email
      if (newEmail != _originalEmail) {
        await supabase.auth.updateUser(UserAttributes(email: newEmail));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Profile updated! Check your new email for a confirmation link."),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profile updated successfully!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      if (mounted) Navigator.pop(context);
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Edit Profile",
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(
            color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveProfile,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Save",
                    style: TextStyle(
                      color: AppColors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    )),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Avatar
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.blue.withOpacity(0.1),
                    child: Text(
                      _nameCtrl.text.isNotEmpty
                          ? _nameCtrl.text[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.blue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Name field
            const Text("Display Name",
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black54)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: "Enter your name",
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.grey.withOpacity(0.15)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.blue, width: 1.5),
                ),
              ),
              validator: (val) => (val == null || val.trim().isEmpty)
                  ? 'Name is required'
                  : null,
            ),

            const SizedBox(height: 24),

            // Email field
            const Text("Email Address",
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black54)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: "Enter your email",
                prefixIcon: const Icon(Icons.email_outlined),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: Colors.grey.withOpacity(0.15)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppColors.blue, width: 1.5),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Email is required';
                }
                if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$')
                    .hasMatch(val.trim())) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),

            if (_isGoogleUser) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.orange.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Changing your email will require verification. "
                        "Your Google login will still work.",
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ------------------------------------------------------
/// 🔔 NOTIFICATIONS PAGE
/// ------------------------------------------------------
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _pushEnabled = true;
  bool _emailEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Notifications", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SettingsTile(
            icon: Icons.notifications_active_outlined,
            title: "Push Notifications",
            trailing: Switch(
              value: _pushEnabled,
              activeColor: AppColors.blue,
              onChanged: (val) => setState(() => _pushEnabled = val),
            ),
          ),
          SettingsTile(
            icon: Icons.mail_outline,
            title: "Email Updates",
            trailing: Switch(
              value: _emailEnabled,
              activeColor: AppColors.blue,
              onChanged: (val) => setState(() => _emailEnabled = val),
            ),
          ),
        ],
      ),
    );
  }
}

/// ------------------------------------------------------
/// 🛠️ HELPER WIDGETS
/// ------------------------------------------------------

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? textColor;
  final Color? iconColor;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.textColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (iconColor ?? Colors.black).withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor ?? Colors.black87),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: textColor ?? Colors.black87,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle!, style: TextStyle(color: Colors.grey[600], fontSize: 12))
            : null,
        trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
  
}
