import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';


class NotificationListPage extends StatelessWidget {
  const NotificationListPage({super.key});

  // 🔥 NEW: Professional Detail View
  void _showNotificationDetails(BuildContext context, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 24,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.blue.withOpacity(0.12),
                    child: const Icon(Icons.notifications_rounded, color: AppColors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item['title'] ?? 'Notification',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                timeago.format(DateTime.parse(item['created_at'])),
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              const Divider(height: 32),
              if (item['image_url'] != null && item['image_url'].toString().trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 250),
                      color: Colors.grey[100],
                      child: Image.network(
                        item['image_url'].toString().trim(),
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return SizedBox(
                            height: 150,
                            child: Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / (loadingProgress.expectedTotalBytes ?? 1)
                                    : null,
                                strokeWidth: 2,
                                color: AppColors.blue,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 150,
                          color: Colors.grey[200],
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text("Image unavailable", style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Text(
                item['body'] ?? '',
                style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
              ),
              const SizedBox(height: 40),
              if (item['action_link'] != null && item['action_link'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final url = Uri.parse(item['action_link']);
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: const Text("Open Link", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text("Please log in")));
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.blue, AppColors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 8),
                const Text(
                  "Notifications",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                ),
                IconButton(
                  tooltip: "Mark all as read",
                  icon: const Icon(Icons.done_all, color: Colors.white),
                  onPressed: () async {
                    await supabase.from('notifications').update({'is_read': true}).eq('user_id', userId);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('notifications')
            .stream(primaryKey: ['id'])
            .eq('user_id', userId)
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_rounded, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 18),
                  const Text(
                    "No notifications yet",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "You're all caught up!",
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final item = notifications[index];
              final bool isRead = item['is_read'] ?? false;
              final DateTime created = DateTime.parse(item['created_at']);

              return Dismissible(
                key: Key(item['id'].toString()),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) async {
                  await supabase.from('notifications').delete().eq('id', item['id']);
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.delete_forever, color: Colors.white, size: 30),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: isRead ? Colors.white : AppColors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: isRead ? Colors.grey[200] : AppColors.blue,
                          child: Icon(
                            isRead ? Icons.notifications_none : Icons.notifications_active,
                            color: isRead ? Colors.grey : Colors.white,
                            size: 22,
                          ),
                        ),
                        if (!isRead)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: AppColors.blue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      item['title'] ?? 'Notification',
                      style: TextStyle(
                        fontWeight: isRead ? FontWeight.w500 : FontWeight.w800,
                        fontSize: 16.5,
                        color: Colors.black87,
                        letterSpacing: -0.2,
                      ),
                    ),
                    subtitle: Text(
                      item['body'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeago.format(created, locale: 'en_short'),
                          style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                        ),
                        if ((item['image_url'] != null && item['image_url'].toString().trim().isNotEmpty) || (item['action_link'] != null && item['action_link'].toString().trim().isNotEmpty))
                          const SizedBox(height: 6),
                        if ((item['image_url'] != null && item['image_url'].toString().trim().isNotEmpty) || (item['action_link'] != null && item['action_link'].toString().trim().isNotEmpty))
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item['image_url'] != null && item['image_url'].toString().trim().isNotEmpty)
                                Icon(Icons.image_rounded, size: 14, color: AppColors.blue.withOpacity(0.6)),
                              if (item['image_url'] != null && item['image_url'].toString().trim().isNotEmpty && item['action_link'] != null && item['action_link'].toString().trim().isNotEmpty)
                                const SizedBox(width: 6),
                              if (item['action_link'] != null && item['action_link'].toString().trim().isNotEmpty)
                                Icon(Icons.link_rounded, size: 14, color: AppColors.purple.withOpacity(0.6)),
                            ],
                          ),
                      ],
                    ),
                    onTap: () async {
                      if (!isRead) {
                        await supabase.from('notifications').update({'is_read': true}).eq('id', item['id']);
                      }
                      _showNotificationDetails(context, item);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}