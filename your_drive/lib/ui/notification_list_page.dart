import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationListPage extends StatelessWidget {
  const NotificationListPage({super.key});

  // 🔥 NEW: Professional Detail View
  void _showNotificationDetails(BuildContext context, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
              Text(
                item['title'] ?? 'Notification',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                timeago.format(DateTime.parse(item['created_at'])),
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              const Divider(height: 32),
              Text(
                item['body'] ?? '',
                style: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
  // ✅ Move 'const' here specifically
                  padding: const EdgeInsets.symmetric(vertical: 16), 
  // ❌ No 'const' on this line
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
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text("Notifications", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: "Mark all as read",
            icon: const Icon(Icons.done_all, color: Colors.blue),
            onPressed: () async {
              await supabase.from('notifications').update({'is_read': true}).eq('user_id', userId);
            },
          ),
        ],
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
            return const Center(child: Text("No notifications yet")); // You can keep your custom empty UI here
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
                  padding: const EdgeInsets.only(right: 20),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.delete_forever, color: Colors.white),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isRead ? Colors.white : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: CircleAvatar(
                      backgroundColor: isRead ? Colors.grey[200] : Colors.blue,
                      child: Icon(
                        isRead ? Icons.notifications_none : Icons.notifications_active,
                        color: isRead ? Colors.grey : Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      item['title'] ?? 'Notification',
                      style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
                    ),
                    subtitle: Text(
                      item['body'] ?? '',
                      maxLines: 1, // Keep list clean, show full text in modal
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      timeago.format(created, locale: 'en_short'),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    onTap: () async {
                      // 1. Mark as read in DB
                      if (!isRead) {
                        await supabase.from('notifications').update({'is_read': true}).eq('id', item['id']);
                      }
                      // 2. 🔥 Show professional details modal
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