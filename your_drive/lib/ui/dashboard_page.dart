import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:your_drive/ui/profile_page.dart';
import '../theme/app_colors.dart';
import '../services/backup_service.dart'; // ✅ Import Backup Service

import 'widgets/category_card.dart';
// import 'widgets/progress_card.dart'; // ❌ Removed static card
import 'widgets/folder_card.dart';
import 'widgets/bottom_nav_bar.dart';

import 'files_page.dart';
import 'upload_page.dart';
import 'create_folder_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<List<Map<String, dynamic>>> foldersFuture;
  
  // ✅ Instantiate the Backup Service
  final backupService = BackupService();

  // ✅ Variables to store real file counts
  int photoCount = 0;
  int videoCount = 0;
  int musicCount = 0;
  int appCount = 0;

  @override
  void initState() {
    super.initState();
    foldersFuture = fetchFolders();
    _fetchFileCounts(); 
  }

  /// 📂 FETCH USER FOLDERS
  Future<List<Map<String, dynamic>>> fetchFolders() async {
    final supabase = Supabase.instance.client;

    final res = await supabase
        .from('folders')
        .select()
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// 🔢 FETCH REAL FILE COUNTS
  Future<void> _fetchFileCounts() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    
    if (user == null) return;

    final response = await supabase
        .from('files')
        .select('type')
        .eq('user_id', user.id);

    int p = 0; // Photos
    int v = 0; // Videos
    int m = 0; // Music
    int a = 0; // Apps

    for (var file in response) {
      final type = file['type'];
      if (type == 'image') p++;
      else if (type == 'video') v++;
      else if (type == 'music') m++;
      else if (type == 'app') a++;
    }

    if (mounted) {
      setState(() {
        photoCount = p;
        videoCount = v;
        musicCount = m;
        appCount = a;
      });
    }
  }

  /// 🔄 REFRESH DATA
  void _refreshAllData() {
    setState(() {
      foldersFuture = fetchFolders();
    });
    _fetchFileCounts();
  }

  /// 🗑 DELETE FOLDER LOGIC
  Future<void> _deleteFolder(String folderId) async {
    final supabase = Supabase.instance.client;
    try {
      // 1. Delete files inside
      await supabase.from('files').delete().eq('folder_id', folderId);

      // 2. Delete folder
      final List<dynamic> deletedRows = await supabase
          .from('folders')
          .delete()
          .eq('id', folderId)
          .select();

      if (deletedRows.isEmpty) {
        throw Exception("Permission denied: Check Supabase RLS Policies");
      }

      _refreshAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Folder deleted successfully")),
        );
      }
    } catch (e) {
      debugPrint("DELETE ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to delete. Check Database Permissions."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ⚠️ SHOW DELETE CONFIRMATION DIALOG
  void _showDeleteDialog(Map<String, dynamic> folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Folder?"),
        content: Text("Are you sure you want to delete '${folder['name']}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _deleteFolder(folder['id']); // Call delete function
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 📏 RESPONSIVE CHECK
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth > 600;

    final int crossAxisCount = isDesktop ? 4 : 2;

    return Scaffold(
      backgroundColor: AppColors.bg,

      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            // HIDE SCROLLBAR
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: ListView(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 120,
                ),
                children: [
                  /// HEADER
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "My storage",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfilePage(),
                            ),
                          ).then((_) => _refreshAllData());
                        },
                        child: const CircleAvatar(
                          child: Icon(Icons.person),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  /// SEARCH
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Search",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white24,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// CATEGORIES
                  Row(
                    children: [
                      Expanded(
                        child: CategoryCard(
                          icon: Icons.image,
                          title: "Photos",
                          percent: "$photoCount files",
                          color: AppColors.blue,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FilesPage(type: 'image'),
                              ),
                            ).then((_) => _refreshAllData());
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CategoryCard(
                          icon: Icons.videocam,
                          title: "Videos",
                          percent: "$videoCount files",
                          color: AppColors.purple,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FilesPage(type: 'video'),
                              ),
                            ).then((_) => _refreshAllData());
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: CategoryCard(
                          icon: Icons.music_note,
                          title: "Music",
                          percent: "$musicCount files",
                          color: AppColors.green,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FilesPage(type: 'music'),
                              ),
                            ).then((_) => _refreshAllData());
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CategoryCard(
                          icon: Icons.apps,
                          title: "Apps",
                          percent: "$appCount files",
                          color: AppColors.orange,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FilesPage(type: 'app'),
                              ),
                            ).then((_) => _refreshAllData());
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  /// ✅ REAL DYNAMIC PROGRESS CARD
                  // Listens to the backup service status
                  ValueListenableBuilder<double>(
                    valueListenable: backupService.progressNotifier,
                    builder: (context, progress, child) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.cloud_sync, color: Colors.black87),
                                    const SizedBox(width: 10),
                                    ValueListenableBuilder<String>(
                                      valueListenable: backupService.statusNotifier,
                                      builder: (context, status, _) => Text(
                                        status == "Idle" ? "Ready to Backup" : status,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                // Start Backup Button
                                IconButton(
                                  onPressed: () {
                                    backupService.startAutoBackup();
                                  },
                                  icon: const CircleAvatar(
                                    radius: 14,
                                    backgroundColor: AppColors.blue,
                                    child: Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // Progress Bar
                            LinearProgressIndicator(
                              value: progress > 0 ? progress : null, // Indeterminate if 0
                              backgroundColor: Colors.grey[200],
                              color: AppColors.purple,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            const SizedBox(height: 8),
                            
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Auto-sync gallery", style: TextStyle(color: Colors.black54, fontSize: 12)),
                                Text("${(progress * 100).toInt()}%", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                              ],
                            )
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  /// FOLDERS TITLE
                  const Text(
                    "All folders",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 12),

                  /// 📁 DYNAMIC FOLDERS
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: foldersFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox.shrink();
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text("No folders yet"),
                        );
                      }

                      final folders = snapshot.data!;

                      return GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.1,
                        children: folders.map<Widget>((folder) {
                          return FolderCard(
                            icon: Icons.folder,
                            title: folder['name'],
                            info: "Tap to open",
                            color: AppColors.blue,
                            onLongPress: () => _showDeleteDialog(folder),
                            onDelete: () => _showDeleteDialog(folder),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FilesPage(
                                    type: 'all',
                                    folderId: folder['id'],
                                  ),
                                ),
                              ).then((_) => _refreshAllData());
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      /// 🔻 BOTTOM NAV BAR
      bottomNavigationBar: BottomNavBar(
        onHome: () {},
        onFiles: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FilesPage(type: 'all'),
            ),
          ).then((_) => _refreshAllData());
        },
        onCreateFolder: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CreateFolderPage(),
            ),
          ).then((created) {
            if (created == true) {
              _refreshAllData();
            }
          });
        },
        onProfile: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ProfilePage(),
            ),
          ).then((_) => _refreshAllData());
        },
      ),
    );
  }
}