import 'dart:io'; // ✅ Import for Platform check
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// ✅ IMPORT SERVICES & PAGES
import 'services/backup_service.dart';
import 'auth/login_page.dart';
import 'ui/dashboard_page.dart';
import 'ui/onboarding_page.dart';
import 'services/biometric_service.dart';

// 🔔 1. BACKGROUND NOTIFICATION HANDLER
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Only run on Mobile
  if (Platform.isAndroid || Platform.isIOS) {
    await Firebase.initializeApp();
    print("Handling a background message: ${message.messageId}");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 2. INIT FIREBASE (Skip on Windows)
  if (!Platform.isWindows) {
    try {
      await Firebase.initializeApp();
      
      // 🔔 4. SETUP NOTIFICATIONS
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      await setupNotifications();
    } catch (e) {
      print("Firebase Init Error: $e");
    }
  }

  // 🔥 3. INIT SUPABASE
  await Supabase.initialize(
    url: 'https://knzogkwgczsnfaypokto.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtuem9na3dnY3pzbmZheXBva3RvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMTUzNjEsImV4cCI6MjA4NTc5MTM2MX0.i-aHu3ZcbtN2WPgLl8nvY6m5fhKgeNlwnZt-QMwRQFg',
  );

  // ✅ 5. INIT BACKUP SERVICE
  await BackupService().initBackgroundService();

  // ✅ 6. CHECK ONBOARDING STATUS
  final prefs = await SharedPreferences.getInstance();
  final bool seenOnboarding = prefs.getBool('seen_onboarding') ?? false;

  runApp(MyDriveApp(seenOnboarding: seenOnboarding));
}

// 🔔 HELPER: REQUEST PERMISSION & GET TOKEN
Future<void> setupNotifications() async {
  // Skip on Windows
  if (Platform.isWindows) return;

  final messaging = FirebaseMessaging.instance;

  // Request Permission
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('User granted permission');
    
    try {
      // Get Device Token
      String? token = await messaging.getToken();
      print("🔥 FCM Token: $token");

      // Save token to Supabase if logged in
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && token != null) {
        await Supabase.instance.client.from('profiles').upsert({
          'id': user.id,
          'fcm_token': token,
        });
      }
    } catch (e) {
      print("Error getting FCM token: $e");
    }
  }
}

class MyDriveApp extends StatelessWidget {
  final bool seenOnboarding;

  const MyDriveApp({super.key, required this.seenOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Drive',
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: seenOnboarding ? const AuthGate() : const OnboardingPage(),
    );
  }
}

/// ------------------------------------------------------
/// 🔒 AUTH GATE (Handles Biometric Lock)
/// ------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLocked = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSecuritySettings();
  }

  /// 🕵️‍♂️ Check if we need to lock the app
  Future<void> _checkSecuritySettings() async {
    // 1. Check if user is actually logged in first
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // Not logged in, so no need to lock. Go to Login.
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 2. Check if Biometric is enabled in settings
    final prefs = await SharedPreferences.getInstance();
    final bioEnabled = prefs.getBool('biometric_enabled') ?? false;

    if (bioEnabled) {
      if (mounted) {
        setState(() {
          _isLocked = true;
          _isLoading = false;
        });
      }
      // 🚀 Trigger scan immediately
      _unlockApp();
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 🔓 Trigger Biometric Scan
  Future<void> _unlockApp() async {
    bool authenticated = await BiometricService.authenticate();
    if (authenticated && mounted) {
      setState(() => _isLocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // 1. Wait for auth stream
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final session = supabase.auth.currentSession;

        // 2. If Not Logged In -> Go to Login
        if (session == null) {
          return const LoginPage();
        }

        // 3. If Logged In...
        // ...but we are still checking settings -> Loading
        if (_isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // ...and App is LOCKED -> Show Lock Screen
        if (_isLocked) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 80, color: Colors.blue),
                  const SizedBox(height: 20),
                  const Text("App Locked", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text("Authentication required"),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: _unlockApp,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text("Unlock Now"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 4. If Unlocked -> Show Dashboard
        return const DashboardPage();
      },
    );
  }
}