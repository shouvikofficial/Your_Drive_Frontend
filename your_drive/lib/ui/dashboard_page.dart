import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:your_drive/ui/profile_page.dart';
import '../theme/app_colors.dart';
import '../services/backup_service.dart';
import '../services/file_service.dart';
import '../services/upload_manager.dart'; // ✅ Import UploadManager
import 'widgets/category_card.dart';
import 'widgets/folder_card.dart';
import 'widgets/bottom_nav_bar.dart';
import 'files_page.dart';
import 'create_folder_page.dart';
import 'notification_list_page.dart';
import 'upload_page.dart'; // ✅ Import UploadPage for navigation

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<Map<String, dynamic>>> foldersFuture;
  final backupService = BackupService();
  int photoCount = 0;
  int videoCount = 0;
  int musicCount = 0;
  int docCount = 0;
  
  @override
  void initState() {
    super.initState();
    _refreshAllData();
  }

// ============================================================
// DATA LOGIC
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

  Future _fetchFileCounts() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

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
  }

  void _refreshAllData() {
    setState(() {
      foldersFuture = fetchFolders();
    });
    _fetchFileCounts();
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
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Rename failed: Blocked by database permissions (RLS)"),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            child: const Text(
              "Rename", 
              style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold)
            ),
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
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
    return ListenableBuilder(
      listenable: UploadManager(),
      builder: (context, child) {
        final manager = UploadManager();
        final isUploading = manager.isUploading;

        // Calculate total pending items
        final pendingCount = manager.uploadQueue
            .where((i) => i.status == 'waiting' || i.status == 'uploading')
            .length;

        final hasUploads = pendingCount > 0 || isUploading;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Left: Title Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Storage",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "My Cloud",
                  style: TextStyle(
                    fontSize: 32, // Larger, bolder title
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    letterSpacing: -1.2, // Tight tracking for modern look
                    height: 1.0,
                  ),
                ),
              ],
            ),

            // Right: Upload Status Pill (Conditional)
            if (hasUploads)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const UploadPage()));
                    },
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: AppColors.blue.withOpacity(0.2), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isUploading)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.blue),
                                strokeCap: StrokeCap.round,
                              ),
                            )
                          else
                            const Icon(
                                Icons.cloud_queue_rounded,
                                size: 18,
                                color: AppColors.blue),
                          const SizedBox(width: 8),
                          Text(
                            isUploading
                                ? "Uploading..."
                                : "$pendingCount Pending",
                            style: const TextStyle(
                              color: AppColors.blue,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
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
      child: TextField(
        decoration: InputDecoration(
          hintText: "Search your files...",
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
          prefixIcon: const Icon(Icons.search, color: AppColors.blue),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
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
                  title: "Documents",
                  percent: "$docCount files",
                  color: Colors.teal,
                  onTap: () => _navToPage(const FilesPage(type: 'document')))),
        ]),
      ],
    );
  }

  Widget _buildBackupCard() {
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
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  backgroundColor: Colors.white12,
                  color: Colors.white,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<String>(
                valueListenable: backupService.statusNotifier,
                builder: (_, status, __) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(status == "Idle" ? "Everything up to date" : status,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    if (progress > 0)
                      Text("${(progress * 100).toInt()}%",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
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

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            final folder = snapshot.data![index];

            return FolderCard(
              icon: Icons.folder_rounded,
              title: folder['name'],
              info: "Items inside",
              color: AppColors.blue,
              onTap: () =>
                  _navToPage(FilesPage(type: 'all', folderId: folder['id'])),
              
              // ✅ Updated Bottom Sheet Actions
              onDelete: () => _showDeleteDialog(folder),
              onRename: () => _showRenameDialog(folder), // This now correctly triggers the popup!
              onShare: () {
                debugPrint("Share ${folder['name']}");
              },
              onStar: () {
                debugPrint("Star ${folder['name']}");
              },
            );
          },
        );
      },
    );
  }
}