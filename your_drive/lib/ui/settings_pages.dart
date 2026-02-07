import 'package:flutter/material.dart';
import '../theme/app_colors.dart'; // Make sure this path matches your project structure

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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Privacy & Security", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionHeader(title: "Security"),
          SettingsTile(
            icon: Icons.fingerprint,
            title: "Biometric Unlock",
            subtitle: "Use FaceID / Fingerprint to open app",
            trailing: Switch(
              value: _biometricEnabled,
              activeColor: AppColors.blue,
              onChanged: (val) => setState(() => _biometricEnabled = val),
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
/// 🛠️ HELPER WIDGETS (To make code cleaner)
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