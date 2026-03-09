import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:your_drive/ui/profile_page.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../theme/app_colors.dart';
import '../services/backup_service.dart';
import '../services/file_service.dart';
import '../services/upload_manager.dart';
import 'widgets/category_card.dart';
import 'widgets/folder_card.dart';
import 'widgets/bottom_nav_bar.dart';
import 'files_page.dart';
import 'create_folder_page.dart';
import 'notification_list_page.dart';
import 'upload_page.dart';
import 'search_page.dart';
import 'settings_pages.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final backupService = BackupService();

  // ── Folder state (replaces FutureBuilder) ──
  List<Map<String, dynamic>> folders = [];
  bool isLoadingFolders = true;
  String? folderError;

  // ── Category counts ──
  int photoCount = 0;
  int videoCount = 0;
  int musicCount = 0;
  int docCount = 0;

  // ── Backup status ──
  bool _isBackupEnabled = false;

  Future<void> _precacheProfileImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final avatarUrl = prefs.getString('user_avatar_url');
      if (avatarUrl != null && mounted) {
        precacheImage(NetworkImage(avatarUrl), context);
      }
    } catch (e) {
      debugPrint("Precache on dashboard error: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshAllData();
    _checkBackupStatus();
    _precacheProfileImage();
  }

  Future<void> _checkBackupStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isBackupEnabled = prefs.getBool('backup_enabled') ?? false;
      });
    }
  }

  Future<void> _enableBackup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('backup_enabled', true);
    if (mounted) {
      setState(() => _isBackupEnabled = true);
    }
    backupService.startAutoBackup();
  }

// ============================================================
// DATA LOGIC
// ============================================================
  Future<void> _loadFolders() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (mounted)
          setState(() {
            folders = [];
            isLoadingFolders = false;
          });
        return;
      }

      final res = await supabase
          .from('folders')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        folders = List<Map<String, dynamic>>.from(res);
        isLoadingFolders = false;
        folderError = null;
      });
    } catch (e) {
      debugPrint("FOLDER LOAD ERROR: $e");
      if (!mounted) return;
      setState(() {
        isLoadingFolders = false;
        folderError = e.toString();
      });
    }
  }

  Future<void> _fetchFileCounts() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    try {
      final results = await Future.wait([
        supabase
            .from('files')
            .count(CountOption.exact)
            .eq('user_id', user.id)
            .eq('type', 'image'),
        supabase
            .from('files')
            .count(CountOption.exact)
            .eq('user_id', user.id)
            .eq('type', 'video'),
        supabase
            .from('files')
            .count(CountOption.exact)
            .eq('user_id', user.id)
            .eq('type', 'music'),
        supabase
            .from('files')
            .count(CountOption.exact)
            .eq('user_id', user.id)
            .eq('type', 'document'),
      ]);

      if (!mounted) return;

      setState(() {
        photoCount = results[0];
        videoCount = results[1];
        musicCount = results[2];
        docCount = results[3];
      });
    } catch (e) {
      debugPrint("FILE COUNT ERROR: $e");
    }
  }

  Future<void> _refreshAllData() async {
    if (mounted) {
      setState(() {
        isLoadingFolders = true;
        folderError = null;
      });
    }
    await Future.wait([_loadFolders(), _fetchFileCounts()]);
    _checkBackupStatus();
  }

  Future _deleteFolder(String folderId) async {
    final supabase = Supabase.instance.client;
    final fileService = FileService();

    try {
      final internalFiles = await supabase
          .from('files')
          .select('id, message_id')
          .eq('folder_id', folderId);

      await Future.wait(internalFiles.map((f) {
        return fileService.deleteFile(
          messageId: f['message_id'],
          supabaseId: f['id'],
          onSuccess: (_) {},
          onError: (_) {},
        );
      }));

      await supabase.from('folders').delete().eq('id', folderId);
      _refreshAllData();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Folder deleted")));
      }
    } catch (e) {
      debugPrint("DELETE ERROR: $e");
    }
  }

  void _showDeleteDialog(Map<String, dynamic> folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Folder?"),
        content: Text(
            "Delete '${folder['name']}' and its contents? This cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteFolder(folder['id']);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NEW RENAME LOGIC
  // ============================================================
  Future<void> _renameFolder(dynamic folderId, String newName) async {
    if (newName.trim().isEmpty) return; // Don't allow empty names

    try {
      // Added .select() to force Supabase to return the updated row
      final response = await Supabase.instance.client
          .from('folders')
          .update({'name': newName.trim()})
          .eq('id', folderId)
          .select();

      // If response is empty, it means 0 rows were updated (Blocked by RLS!)
      if (response.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text("Rename failed: Blocked by database permissions (RLS)"),
            backgroundColor: Colors.redAccent,
          ));
        }
        return;
      }

      _refreshAllData(); // Refresh the grid to show the new name

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Folder renamed successfully")));
      }
    } catch (e) {
      debugPrint("RENAME ERROR: $e");
    }
  }

  void _showRenameDialog(Map<String, dynamic> folder) {
    final TextEditingController controller =
        TextEditingController(text: folder['name']); // Pre-fill current name

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Rename Folder"),
        content: TextField(
          controller: controller,
          autofocus: true, // Automatically pops up the keyboard
          decoration: InputDecoration(
            hintText: "Enter new folder name",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text;
              Navigator.pop(context); // Close the dialog
              _renameFolder(folder['id'], newName); // Save the new name
            },
            child: const Text("Rename",
                style: TextStyle(
                    color: AppColors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future _navToPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _refreshAllData();
  }

// ============================================================
// UI BUILD
// ============================================================
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;
    final crossAxisCount = isDesktop ? 4 : 2;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: RefreshIndicator(
              onRefresh: _refreshAllData,
              color: AppColors.blue,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildSearchBar(),
                  const SizedBox(height: 30),
                  _buildCategoryGrid(),
                  const SizedBox(height: 30),
                  _buildBackupCard(),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("All Folders",
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5)),
                      TextButton(
                          onPressed: _refreshAllData,
                          child: const Text("Refresh",
                              style: TextStyle(color: AppColors.blue))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildFolderGrid(crossAxisCount),
                  const SizedBox(height: 120), // Bottom padding for nav bar
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('notifications')
            .stream(primaryKey: ['id']).eq('user_id', userId ?? ''),
        builder: (context, snapshot) {
          final notifications = snapshot.data ?? [];
          final unreadCount =
              notifications.where((n) => n['is_read'] == false).length;

          return BottomNavBar(
            unreadCount: unreadCount,
            onHome: _refreshAllData,
            onFiles: () => _navToPage(const FilesPage(type: 'all')),
            onCreateFolder: () => _navToPage(const CreateFolderPage()),
            onProfile: () => _navToPage(const ProfilePage()),
            onNotifications: () => _navToPage(const NotificationListPage()),
          );
        },
      ),
    );
  }

// ✅ UPDATED HEADER WITH BACKGROUND UPLOAD INDICATOR
  Widget _buildHeader() {
    final manager = UploadManager();

    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final isUploading = manager.isUploadingNotifier.value;
        final hasPaused = manager.uploadQueue.any((i) => i.status == 'paused' || i.status == 'waiting');
        final hasFailed = manager.uploadQueue.any((i) => i.status == 'error' || i.status == 'no_internet');
        
        final pausedOrWaitingCount = manager.uploadQueue.where((i) => i.status == 'paused' || i.status == 'waiting').length;
        final failedCount = manager.uploadQueue.where((i) => i.status == 'error' || i.status == 'no_internet').length;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Branded logo + title ──
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.blue, AppColors.purple],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.blue.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Cloud Guard",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Encrypted cloud vault",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // ── Upload / Paused status pill ──
            if (isUploading)
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UploadPage()),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.blue.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.blue),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Uploading",
                        style: TextStyle(
                          color: AppColors.blue,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (hasFailed)
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UploadPage()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.red.withOpacity(0.15), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 15, color: Colors.red),
                      const SizedBox(width: 6),
                      Text(
                        "$failedCount Failed",
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              )
            else if (hasPaused)
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UploadPage()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.orange.withOpacity(0.15), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pause_circle_filled, size: 15, color: Colors.orange),
                      const SizedBox(width: 6),
                      Text(
                        "$pausedOrWaitingCount Paused",
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SearchPage(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 250),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, 8))
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.blue, size: 22),
            const SizedBox(width: 12),
            Text(
              "Search your files...",
              style: TextStyle(color: Colors.grey[400], fontSize: 15),
            ),
            const Spacer(),
            Icon(Icons.tune_rounded, color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    return Column(
      children: [
        Row(children: [
          Expanded(
              child: CategoryCard(
                  icon: Icons.image,
                  title: "Photos",
                  percent: "$photoCount files",
                  color: AppColors.blue,
                  onTap: () => _navToPage(const FilesPage(type: 'image')))),
          const SizedBox(width: 16),
          Expanded(
              child: CategoryCard(
                  icon: Icons.videocam,
                  title: "Videos",
                  percent: "$videoCount files",
                  color: AppColors.purple,
                  onTap: () => _navToPage(const FilesPage(type: 'video')))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: CategoryCard(
                  icon: Icons.music_note,
                  title: "Music",
                  percent: "$musicCount files",
                  color: AppColors.green,
                  onTap: () => _navToPage(const FilesPage(type: 'music')))),
          const SizedBox(width: 16),
          Expanded(
              child: CategoryCard(
                  icon: Icons.description_rounded,
                  title: "Doc",
                  percent: "$docCount files",
                  color: Colors.teal,
                  onTap: () => _navToPage(const FilesPage(type: 'document')))),
        ]),
      ],
    );
  }

  Widget _buildBackupCard() {
    // ── BACKUP OFF STATE ──
    if (!_isBackupEnabled) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Cloud-off icon with orange accent
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.cloud_off_rounded,
                      color: Colors.orange.shade700, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Backup is off",
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      const SizedBox(height: 4),
                      Text(
                        "Your photos & videos are not being backed up",
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BackupSettingsPage()),
                      );
                      _checkBackupStatus();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text("Settings",
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _enableBackup,
                    icon: const Icon(Icons.cloud_upload_rounded, size: 20),
                    label: const Text("Turn on backup",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // ── BACKUP ON STATE ──
    return ValueListenableBuilder<double>(
      valueListenable: backupService.progressNotifier,
      builder: (context, progress, _) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [AppColors.blue, AppColors.blue.withOpacity(0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: AppColors.blue.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Auto Backup",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text("Cloud Sync Active",
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => backupService.startAutoBackup(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: Colors.white24, shape: BoxShape.circle),
                      child: const Icon(Icons.sync, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (progress > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    color: Colors.white,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ValueListenableBuilder<String>(
                valueListenable: backupService.statusNotifier,
                builder: (_, status, __) {
                  return StreamBuilder<List<ConnectivityResult>>(
                    stream: Connectivity().onConnectivityChanged,
                    builder: (context, snapshot) {
                      final isWaiting = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;
                      final isOffline = !isWaiting && 
                          snapshot.hasData && 
                          snapshot.data!.isNotEmpty && 
                          snapshot.data!.every((r) => r == ConnectivityResult.none);

                      if (isOffline) {
                        return const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.cloud_off_rounded,
                                      color: Colors.white70, size: 16),
                                ),
                                Text(
                                  "Waiting for internet connection...",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }

                      final isIdle = status == "Idle" || progress <= 0;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isIdle)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.check_circle_rounded,
                                      color: Colors.white70, size: 16),
                                ),
                              Text(
                                isIdle ? "Everything up to date" : status,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          if (progress > 0)
                            Text("${(progress * 100).toInt()}%",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderGrid(int crossAxisCount) {
    // ── Loading: Google Drive shimmer skeleton ──
    if (isLoadingFolders) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4, // show 4 shimmer placeholders
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) => _buildShimmerCard(),
      );
    }

    // ── Error: retry prompt ──
    if (folderError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.red.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_off_rounded, color: Colors.red[300], size: 48),
            const SizedBox(height: 12),
            const Text("Couldn't load folders",
                style: TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text("Tap to retry",
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _refreshAllData,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text("Retry",
                    style: TextStyle(
                        color: AppColors.blue, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    }

    // ── Empty state ──
    if (folders.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey[200]!)),
        child: Column(
          children: [
            Icon(Icons.create_new_folder_outlined,
                color: Colors.grey[300], size: 48),
            const SizedBox(height: 12),
            const Text("No folders created yet",
                style: TextStyle(color: Colors.black38)),
          ],
        ),
      );
    }

    // ── Folder grid ──
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: folders.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, index) {
        final folder = folders[index];

        return FolderCard(
          icon: Icons.folder_rounded,
          title: folder['name'],
          info: "Items inside",
          color: AppColors.blue,
          onTap: () =>
              _navToPage(FilesPage(type: 'all', folderId: folder['id'])),
          onDelete: () => _showDeleteDialog(folder),
          onRename: () => _showRenameDialog(folder),
          onShare: () {
            debugPrint("Share ${folder['name']}");
          },
          onStar: () {
            debugPrint("Star ${folder['name']}");
          },
        );
      },
    );
  }

  /// Google Drive-style shimmer placeholder card
  Widget _buildShimmerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey[100]!),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(36, 36, radius: 10),
          const Spacer(),
          _shimmerBox(14, 90),
          const SizedBox(height: 6),
          _shimmerBox(11, 60),
        ],
      ),
    );
  }

  Widget _shimmerBox(double height, double width, {double radius = 6}) {
    return _ShimmerBox(height: height, width: width, radius: radius);
  }
}

/// Pulsing shimmer box (repeating animation without a controller)
class _ShimmerBox extends StatefulWidget {
  final double height, width, radius;
  const _ShimmerBox(
      {required this.height, required this.width, this.radius = 6});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.06, end: 0.18).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(_anim.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
