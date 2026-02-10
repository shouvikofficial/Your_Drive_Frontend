import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DevicesSessionsPage extends StatefulWidget {
  const DevicesSessionsPage({super.key});

  @override
  State<DevicesSessionsPage> createState() => _DevicesSessionsPageState();
}

class _DevicesSessionsPageState extends State<DevicesSessionsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  /// 🔹 Load sessions from Supabase
  Future<void> _loadSessions() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final data = await supabase
          .from('sessions')
          .select()
          .eq('user_id', user.id)
          .order('last_active', ascending: false);

      if (mounted) {
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 🔹 Logout specific device
  Future<void> _logoutSession(String sessionId) async {
    final supabase = Supabase.instance.client;

    await supabase.from('sessions').delete().eq('id', sessionId);

    _loadSessions();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Device logged out")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text(
          "Devices & Sessions",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        titleTextStyle: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),

      /// ================= BODY =================
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(
                  child: Text(
                    "No active sessions",
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final s = _sessions[index];

                    return _DeviceTile(
                      deviceName: s['device_name'] ?? "Unknown device",
                      location: _formatLastActive(s['last_active']),
                      isCurrent: s['is_current'] ?? false,
                      onLogout: () => _logoutSession(s['id']),
                    );
                  },
                ),
    );
  }

  /// 🔹 Format last active time
  String _formatLastActive(String? timestamp) {
    if (timestamp == null) return "Unknown activity";

    final dt = DateTime.tryParse(timestamp);
    if (dt == null) return "Unknown activity";

    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return "Active now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hrs ago";

    return "${dt.day}/${dt.month}/${dt.year}";
  }
}

class _DeviceTile extends StatelessWidget {
  final String deviceName;
  final String location;
  final bool isCurrent;
  final VoidCallback? onLogout;

  const _DeviceTile({
    required this.deviceName,
    required this.location,
    required this.isCurrent,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.devices,
            color: isCurrent ? Colors.green : Colors.black54,
          ),
          const SizedBox(width: 12),

          /// TEXT
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  location,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          /// ACTION
          if (!isCurrent)
            TextButton(
              onPressed: onLogout,
              child: const Text(
                "Logout",
                style: TextStyle(color: Colors.red),
              ),
            )
          else
            const Text(
              "Current",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }
}
