import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart'; // 👈 Add this line!
import '../theme/app_colors.dart';
import '../auth/login_page.dart';
import 'settings_pages.dart'; // ✅ Import the file containing BackupSettingsPage

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

  // ⚙️ Backup Status (For Display Only)
  bool _isBackupOn = false;

  @override
  void initState() {
    super.initState();
    _loadCachedProfile(); // ⚡ 1. Load instantly from cache
    loadProfile();        // 🌍 2. Fetch fresh data in background
    _checkBackupStatus(); // ☁️ 3. Check status for "On/Off" text
  }

  /// ⚡ LOAD CACHED DATA (Instant UI)
  Future<void> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        name = prefs.getString('user_name') ?? "User";
        email = prefs.getString('user_email') ?? "";
        // ✅ Load previously calculated storage size
        totalBytesUsed = prefs.getInt('user_storage_used') ?? 0;
        
        // If we have cached data, stop the spinner immediately
        if (name != "User") loading = false;
      });
    }
  }

  /// ☁️ CHECK BACKUP STATUS (Updates the On/Off text)
  Future<void> _checkBackupStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isBackupOn = prefs.getBool('backup_enabled') ?? false;
      });
    }
  }

  /// 📥 LOAD FRESH PROFILE (Background)
  Future<void> loadProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) setState(() => loading = false);
        return;
      }

      // 1. Fetch Profile
      final profileData = await supabase
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();

      // 2. Fetch Files for Storage Calc
      final filesData = await supabase
          .from('files')
          .select('size')
          .eq('user_id', user.id);

      int sum = 0;
      for (var file in filesData) {
        sum += (file['size'] as num? ?? 0).toInt();
      }

      if (!mounted) return;

      final newName = profileData?['name'] ?? 'User';
      final newEmail = user.email ?? '';

      // 💾 Save to Cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', newName);
      await prefs.setString('user_email', newEmail);
      await prefs.setInt('user_storage_used', sum);

      setState(() {
        name = newName;
        email = newEmail;
        totalBytesUsed = sum;
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
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
    // 1. Sign out from Supabase
    await Supabase.instance.client.auth.signOut();
    
    // 2. Clear local storage (Optional but recommended)
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); 

    if (!mounted) return;
    
    // 3. Navigate to Login
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
      ),

      // ✅ INSTANT LOAD: Only show spinner if we have NO cached data (first install)
      body: loading && name == "User"
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
                        _buildProfileOption(
                          Icons.person_outline, 
                          "Account Settings", 
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountSettingsPage()))
                        ),
                        _buildDivider(),
                        
                        // ✅ LINKED TO BACKUP SETTINGS PAGE
                        _buildProfileOption(
                          Icons.cloud_sync_outlined, 
                          "Backup & Sync",
                          onTap: () async {
                             // Navigate and wait for result
                             await Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupSettingsPage()));
                             // Refresh status when user returns
                             _checkBackupStatus(); 
                          }, 
                          trailingText: _isBackupOn ? "On" : "Off", 
                          trailingColor: _isBackupOn ? AppColors.blue : Colors.grey,
                        ),
                        
                        _buildDivider(),
                        _buildProfileOption(
                          Icons.notifications_none, 
                          "Notifications", 
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage()))
                        ),
                        _buildDivider(),
                        _buildProfileOption(
                          Icons.lock_outline, 
                          "Privacy & Security", 
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage()))
                        ),
                        _buildDivider(),
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
  Widget _buildProfileOption(IconData icon, String title, {required VoidCallback onTap, String? trailingText, Color? trailingColor}) {
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
            Text(trailingText, style: TextStyle(color: trailingColor ?? Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
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