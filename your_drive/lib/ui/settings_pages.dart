import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../services/biometric_service.dart'; 
import '../services/backup_service.dart'; // ✅ Import Backup Service

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

          // 📊 LIVE STATUS INDICATOR
          const SizedBox(height: 24),
          ValueListenableBuilder<String>(
            valueListenable: _backupService.statusNotifier,
            builder: (context, status, _) {
              return Center(
                child: Text(
                  "Status: $status",
                  style: TextStyle(color: Colors.grey[600], fontSize: 13, fontStyle: FontStyle.italic),
                ),
              );
            },
          ),
        ],
      ),
    );
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
  bool _twoFactorEnabled = true; 

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
            subtitle: "Use Fingerprint to open app",
            trailing: Switch(
              value: _biometricEnabled,
              activeColor: AppColors.blue,
              onChanged: _toggleBiometric,
            ),
          ),
          SettingsTile(
            icon: Icons.security,
            title: "Two-Factor Authentication",
            subtitle: "Extra layer of security",
            trailing: Switch(
              value: _twoFactorEnabled,
              activeColor: AppColors.blue,
              onChanged: (val) => setState(() => _twoFactorEnabled = val),
            ),
          ),
          SettingsTile(
            icon: Icons.lock_reset,
            title: "Change Password",
            onTap: () {},
          ),

          const SizedBox(height: 24),
          const SectionHeader(title: "Data"),
          SettingsTile(
            icon: Icons.history,
            title: "Clear Search History",
            onTap: () {},
          ),
          SettingsTile(
            icon: Icons.delete_forever,
            title: "Delete Account",
            textColor: Colors.red,
            iconColor: Colors.red,
            onTap: () {},
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
            onTap: () {},
          ),
          SettingsTile(
            icon: Icons.chat_bubble_outline,
            title: "Contact Support",
            subtitle: "We usually reply within 24 hours",
            onTap: () {},
          ),
          
          const SizedBox(height: 24),
          const SectionHeader(title: "Legal"),
          SettingsTile(
            icon: Icons.description_outlined,
            title: "Terms of Service",
            onTap: () {},
          ),
          SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: "Privacy Policy",
            onTap: () {},
          ),
          
          const SizedBox(height: 40),
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
/// 👤 ACCOUNT SETTINGS PAGE
/// ------------------------------------------------------
class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({super.key});

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
            onTap: () {},
          ),
          SettingsTile(
            icon: Icons.email_outlined,
            title: "Change Email",
            onTap: () {},
          ),
        ],
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