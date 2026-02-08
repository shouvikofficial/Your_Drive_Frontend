import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:your_drive/ui/profile_page.dart';
import '../theme/app_colors.dart';
import '../services/backup_service.dart';
import '../services/file_service.dart';

import 'widgets/category_card.dart';
import 'widgets/folder_card.dart';
import 'widgets/bottom_nav_bar.dart';

import 'files_page.dart';
import 'create_folder_page.dart';
import 'notification_list_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<Map<String, dynamic>>> foldersFuture;

  final backupService = BackupService();

  int photoCount = 0;
  int videoCount = 0;
  int musicCount = 0;
  int appCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshAllData();
  }

  // ============================================================
  // FETCH USER FOLDERS
  // ============================================================
  Future<List<Map<String, dynamic>>> fetchFolders() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return [];

    final res = await supabase
        .from('folders')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  // ============================================================
  // 🔥 FETCH FILE COUNTS (OPTIMIZED & INSTANT)
  // ============================================================
  Future<void> _fetchFileCounts() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final results = await Future.wait([
      supabase.from('files').count(CountOption.exact).eq('user_id', user.id).eq('type', 'image'),
      supabase.from('files').count(CountOption.exact).eq('user_id', user.id).eq('type', 'video'),
      supabase.from('files').count(CountOption.exact).eq('user_id', user.id).eq('type', 'music'),
      supabase.from('files').count(CountOption.exact).eq('user_id', user.id).eq('type', 'app'),
    ]);

    if (!mounted) return;

    setState(() {
      photoCount = results[0];
      videoCount = results[1];
      musicCount = results[2];
      appCount = results[3];
    });
  }

  // ============================================================
  // REFRESH ALL DATA
  // ============================================================
  void _refreshAllData() {
    setState(() {
      foldersFuture = fetchFolders();
    });
    _fetchFileCounts();
  }

  // ============================================================
  // DELETE FOLDER
  // ============================================================
  Future<void> _deleteFolder(String folderId) async {
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Folder deleted")),
      );
    } catch (e) {
      debugPrint("DELETE ERROR: $e");
    }
  }

  void _showDeleteDialog(Map<String, dynamic> folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Folder?"),
        content: Text("Delete '${folder['name']}' and its contents?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
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
  // 🔥 NAVIGATION FIX (AWAIT RESULT)
  // ============================================================
  Future<void> _navToPage(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      _refreshAllData();
    }
  }

  // ============================================================
  // UI
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
            child: ListView(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildSearchBar(),
                const SizedBox(height: 20),
                _buildCategoryGrid(),
                const SizedBox(height: 20),
                _buildBackupCard(),
                const SizedBox(height: 20),
                const Text("All folders", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _buildFolderGrid(crossAxisCount),
              ],
            ),
          ),
        ),
      ),
      // 🔥 UPDATED: Real-time Listener that works with Flutter
      bottomNavigationBar: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', userId ?? ''), 
        builder: (context, snapshot) {
          // Filter unread count manually to avoid .eq('is_read') stream errors
          final notifications = snapshot.data ?? [];
          final unreadCount = notifications.where((n) => n['is_read'] == false).length;

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

  // ============================================================
  // WIDGETS
  // ============================================================
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("My storage", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        GestureDetector(
          onTap: () => _navToPage(const ProfilePage()),
          child: const CircleAvatar(child: Icon(Icons.person)),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      decoration: InputDecoration(
        hintText: "Search",
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white24,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
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
          const SizedBox(width: 12),
          Expanded(
              child: CategoryCard(
                  icon: Icons.videocam,
                  title: "Videos",
                  percent: "$videoCount files",
                  color: AppColors.purple,
                  onTap: () => _navToPage(const FilesPage(type: 'video')))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: CategoryCard(
                  icon: Icons.music_note,
                  title: "Music",
                  percent: "$musicCount files",
                  color: AppColors.green,
                  onTap: () => _navToPage(const FilesPage(type: 'music')))),
          const SizedBox(width: 12),
          Expanded(
              child: CategoryCard(
                  icon: Icons.apps,
                  title: "Apps",
                  percent: "$appCount files",
                  color: AppColors.orange,
                  onTap: () => _navToPage(const FilesPage(type: 'app')))),
        ]),
      ],
    );
  }

  Widget _buildBackupCard() {
    return ValueListenableBuilder<double>(
      valueListenable: backupService.progressNotifier,
      builder: (context, progress, _) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  const Icon(Icons.cloud_sync, color: Colors.black87),
                  const SizedBox(width: 10),
                  ValueListenableBuilder<String>(
                    valueListenable: backupService.statusNotifier,
                    builder: (_, status, __) => Text(
                      status == "Idle" ? "Ready to Backup" : status,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
                IconButton(
                  onPressed: () => backupService.startAutoBackup(),
                  icon: const CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.blue,
                    child: Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: Colors.grey[200],
                color: AppColors.purple,
                minHeight: 8,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Auto-sync gallery", style: TextStyle(color: Colors.black54, fontSize: 12)),
                Text("${(progress * 100).toInt()}%", style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ])
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderGrid(int crossAxisCount) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: foldersFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Padding(padding: EdgeInsets.all(20), child: Text("No folders yet"));
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
          children: snapshot.data!
              .map<Widget>((folder) => FolderCard(
                    icon: Icons.folder,
                    title: folder['name'],
                    info: "Tap to open",
                    color: AppColors.blue,
                    onLongPress: () => _showDeleteDialog(folder),
                    onDelete: () => _showDeleteDialog(folder),
                    onTap: () => _navToPage(FilesPage(type: 'all', folderId: folder['id'])),
                  ))
              .toList(),
        );
      },
    );
  }
}