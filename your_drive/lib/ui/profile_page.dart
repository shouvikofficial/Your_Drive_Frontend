import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../auth/login_page.dart';
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

  int totalBytesUsed = 0;
  final int maxStorageBytes = 100 * 1024 * 1024 * 1024 * 1024; // 100 TB
  bool _isBackupOn = false;

  @override
  void initState() {
    super.initState();
    _loadCachedProfile();
    loadProfile();
    _checkBackupStatus();
  }

  Future<void> _loadCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        name = prefs.getString('user_name') ?? "User";
        email = prefs.getString('user_email') ?? "";
        totalBytesUsed = prefs.getInt('user_storage_used') ?? 0;
        if (name != "User") loading = false;
      });
    }
  }

  Future<void> _checkBackupStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isBackupOn = prefs.getBool('backup_enabled') ?? false;
      });
    }
  }

  Future<void> loadProfile() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted) setState(() => loading = false);
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

      final newName = profileData?['name'] ?? 'User';
      final newEmail = user.email ?? '';

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

  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _navTo(Widget page, {bool refreshProfile = false}) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (refreshProfile && mounted) {
      _loadCachedProfile();
      loadProfile();
    }
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
      body: loading && name == "User"
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ─── GRADIENT HEADER ───
                SliverToBoxAdapter(
                  child: Container(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 12,
                      bottom: 40,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.blue, AppColors.purple],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(36),
                        bottomRight: Radius.circular(36),
                      ),
                    ),
                    child: Column(
                      children: [
                        // AppBar row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new,
                                    color: Colors.white, size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const Expanded(
                                child: Text(
                                  "Profile",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // Edit profile button
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    color: Colors.white70, size: 20),
                                onPressed: () => _navTo(
                                  const EditProfilePage(),
                                  refreshProfile: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Avatar with gradient ring and fallback icon
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [AppColors.blue, AppColors.purple],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.blue.withOpacity(0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.white.withOpacity(0.10),
                            child: name.isNotEmpty && name.trim() != ''
                                ? Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 38,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.person_rounded, size: 44, color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Name
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Email
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── BODY CONTENT ───
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── STORAGE CARD ──
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter:
                                ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.35)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding:
                                                const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: AppColors.blue
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                              Icons.cloud_outlined,
                                              color: AppColors.blue,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Text(
                                            "Storage",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.orange
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          percentText,
                                          style: const TextStyle(
                                            color: AppColors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  // Progress bar
                                  Stack(
                                    children: [
                                      Container(
                                        height: 8,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          return AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 600),
                                            curve: Curves.easeOut,
                                            height: 8,
                                            width: constraints.maxWidth *
                                                progress,
                                            decoration: BoxDecoration(
                                              gradient:
                                                  const LinearGradient(
                                                colors: [
                                                  AppColors.blue,
                                                  AppColors.purple
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "${_formatSize(totalBytesUsed)} used",
                                        style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12),
                                      ),
                                      const Text(
                                        "Unlimited",
                                        style: TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ── QUICK ACTIONS ──
                        Row(
                          children: [
                            _buildQuickAction(
                              Icons.person_outline_rounded,
                              "Account",
                              AppColors.blue,
                              () => _navTo(const AccountSettingsPage(), refreshProfile: true),
                            ),
                            const SizedBox(width: 12),
                            _buildQuickAction(
                              Icons.lock_outline_rounded,
                              "Security",
                              AppColors.green,
                              () => _navTo(const PrivacyPage()),
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // ── SETTINGS SECTION ──
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.settings, size: 16, color: Colors.grey[500]),
                              const SizedBox(width: 6),
                              const Text(
                                "SETTINGS",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Settings card
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter:
                                ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.35)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  _buildSettingsItem(
                                    Icons.cloud_sync_outlined,
                                    "Backup & Sync",
                                    trailingWidget: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _isBackupOn
                                            ? AppColors.blue
                                                .withOpacity(0.1)
                                            : Colors.grey.withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _isBackupOn ? "On" : "Off",
                                        style: TextStyle(
                                          color: _isBackupOn
                                              ? AppColors.blue
                                              : Colors.grey,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    onTap: () async {
                                      await _navTo(
                                          const BackupSettingsPage());
                                      _checkBackupStatus();
                                    },
                                  ),
                                  _settingsDivider(),
                                  _buildSettingsItem(
                                    Icons.notifications_none_rounded,
                                    "Notifications",
                                    onTap: () => _navTo(
                                        const NotificationsPage()),
                                  ),
                                  _settingsDivider(),
                                  _buildSettingsItem(
                                    Icons.help_outline_rounded,
                                    "Help & Support",
                                    onTap: () =>
                                        _navTo(const HelpPage()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ── LOGOUT BUTTON ──
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: logout,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.withOpacity(0.10),
                              foregroundColor: Colors.red,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(
                                    color: Colors.red.withOpacity(0.18)),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout_rounded, size: 22),
                                SizedBox(width: 10),
                                Text(
                                  "Log Out",
                                  style: TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── APP VERSION ──
                        const Center(
                          child: Text(
                            "Cloud Guard v1.0.0",
                            style: TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Quick action button ──
  Widget _buildQuickAction(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.75),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: Colors.white.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Settings list item ──
  Widget _buildSettingsItem(IconData icon, String title,
      {Widget? trailingWidget, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F9),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: Colors.black87, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
            if (trailingWidget != null) trailingWidget,
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _settingsDivider() {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 60,
      endIndent: 16,
      color: Colors.grey.withOpacity(0.15),
    );
  }
}