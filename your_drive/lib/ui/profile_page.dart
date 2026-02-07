import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../auth/login_page.dart';
import '../services/backup_service.dart';
// ✅ IMPORT THE SETTINGS PAGES
import 'settings_pages.dart'; 

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String name = "User";
  String email = "";
  bool loading = true;
  
  // 📊 Storage Variables
  int totalBytesUsed = 0;
  final int maxStorageBytes = 100 * 1024 * 1024 * 1024 * 1024; // 100 TB

  // ⚙️ Backup Settings State
  bool _backupEnabled = false;
  bool _wifiOnly = true;
  bool _chargingOnly = false;

  @override
  void initState() {
    super.initState();
    loadProfile();
    _loadBackupSettings();
  }

  /// 📥 LOAD PROFILE
  Future<void> loadProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        setState(() => loading = false);
        return;
      }

      final profileData = await supabase
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();

      final filesData = await supabase
          .from('files')
          .select('size')
          .eq('user_id', user.id);

      int sum = 0;
      for (var file in filesData) {
        sum += (file['size'] as num? ?? 0).toInt();
      }

      if (!mounted) return;

      setState(() {
        name = profileData?['name'] ?? 'User';
        email = user.email ?? '';
        totalBytesUsed = sum;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  /// 💾 LOAD SETTINGS
  Future<void> _loadBackupSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backupEnabled = prefs.getBool('backup_enabled') ?? false;
      _wifiOnly = prefs.getBool('wifi_only') ?? true;
      _chargingOnly = prefs.getBool('charging_only') ?? false;
    });
  }

  /// 💾 SAVE SETTINGS
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('backup_enabled', _backupEnabled);
    await prefs.setBool('wifi_only', _wifiOnly);
    await prefs.setBool('charging_only', _chargingOnly);
  }

  /// ⚙️ SHOW BACKUP SETTINGS PANEL
  void _showBackupSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_sync, color: AppColors.blue, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        "Backup & Sync",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Automatically upload photos and videos from this device.",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  /// 1. MASTER TOGGLE
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Back up & sync", style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_backupEnabled ? "On" : "Off"),
                    value: _backupEnabled,
                    activeColor: AppColors.blue,
                    onChanged: (val) {
                      setSheetState(() => _backupEnabled = val);
                      setState(() => _backupEnabled = val);
                      _saveSettings();

                      if (val) {
                        // Start Backup
                        BackupService().startAutoBackup();
                        BackupService().scheduleBackgroundBackup();
                      } else {
                        // Stop Backup
                        BackupService().stopBackup();
                        BackupService().cancelBackgroundBackup();
                      }
                    },
                  ),

                  if (_backupEnabled) ...[
                    const Divider(height: 30),
                    
                    const Text("Cellular Data Usage", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    
                    /// 2. WI-FI ONLY TOGGLE
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Back up over Wi-Fi only"),
                      value: _wifiOnly,
                      activeColor: AppColors.blue,
                      onChanged: (val) {
                        setSheetState(() => _wifiOnly = val);
                        setState(() => _wifiOnly = val);
                        _saveSettings();
                      },
                    ),

                    const SizedBox(height: 10),
                    const Text("Battery Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),

                    /// 3. CHARGING ONLY TOGGLE
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("When charging only"),
                      value: _chargingOnly,
                      activeColor: AppColors.blue,
                      onChanged: (val) {
                        setSheetState(() => _chargingOnly = val);
                        setState(() => _chargingOnly = val);
                        _saveSettings();
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 🧮 HELPER: FORMAT BYTES
  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  /// 🚪 LOGOUT FUNCTION
  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()), 
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    double progress = totalBytesUsed / maxStorageBytes;
    if (progress > 1.0) progress = 1.0;
    
    String percentText;
    if (totalBytesUsed > 0 && progress < 0.01) {
      percentText = "< 1%";
    } else {
      percentText = "${(progress * 100).toInt()}%";
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        title: const Text(
          "Profile",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {}, 
            icon: const Icon(Icons.settings_outlined, color: Colors.black),
          ),
        ],
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  /// 👤 PROFILE HEADER
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [AppColors.blue, AppColors.purple],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white,
                            child: CircleAvatar(
                              radius: 46,
                              backgroundColor: Color(0xFFF3F4F9),
                              child: Icon(Icons.person, size: 50, color: Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  /// 📊 STORAGE STATS CARD
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Storage Used", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    percentText, 
                                    style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Stack(
                              children: [
                                Container(
                                  height: 8,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    return Container(
                                      height: 8,
                                      width: constraints.maxWidth * progress, 
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(colors: [AppColors.blue, AppColors.purple]),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    );
                                  }
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("${_formatSize(totalBytesUsed)} used", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                const Text("Unlimited", style: TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// ⚙️ MENU OPTIONS
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Column(
                      children: [
                        // ✅ LINKED: Account Settings
                        _buildProfileOption(
                          Icons.person_outline, 
                          "Account Settings", 
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsPage()))
                        ),
                        _buildDivider(),
                        
                        // ✅ LINKED: Backup & Sync (Opens Bottom Sheet)
                        _buildProfileOption(
                          Icons.cloud_sync_outlined, 
                          "Backup & Sync",
                          onTap: _showBackupSettings, 
                          trailingText: _backupEnabled ? "On" : "Off", 
                        ),
                        
                        _buildDivider(),
                        // ✅ LINKED: Notifications
                        _buildProfileOption(
                          Icons.notifications_none, 
                          "Notifications", 
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()))
                        ),
                        _buildDivider(),
                        // ✅ LINKED: Privacy
                        _buildProfileOption(
                          Icons.lock_outline, 
                          "Privacy & Security", 
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage()))
                        ),
                        _buildDivider(),
                        // ✅ LINKED: Help
                        _buildProfileOption(
                          Icons.help_outline, 
                          "Help & Support", 
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage()))
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  /// 🚪 LOGOUT BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: logout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4757),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout),
                          SizedBox(width: 8),
                          Text("Log Out", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Helper widget for menu items
  Widget _buildProfileOption(IconData icon, String title, {required VoidCallback onTap, String? trailingText}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.black87, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) 
            Text(trailingText, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
          if (trailingText != null) const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 0.5, indent: 60, endIndent: 20);
  }
}