import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

// ✅ IMPORTS
import 'config/env.dart';
import 'services/backup_service.dart';
import 'auth/login_page.dart';
import 'ui/onboarding_page.dart';
import 'pages/vault_login_page.dart';

// 🔔 BACKGROUND NOTIFICATION HANDLER
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await Firebase.initializeApp();
    print("Handling a background message: ${message.messageId}");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ================= HIVE INIT (🔥 IMPORTANT FIX)
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);

  // open resume upload box
  await Hive.openBox('uploads');
  // ================= END HIVE INIT

  // 🔥 FIREBASE INIT (Skip on Windows)
  if (!Platform.isWindows) {
    try {
      await Firebase.initializeApp();

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      await setupNotifications();
    } catch (e) {
      print("Firebase Init Error: $e");
    }
  }

  // 🔥 SUPABASE INIT
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // ✅ BACKUP SERVICE INIT
  try {
    await BackupService().initBackgroundService();
  } catch (e) {
    print("Backup Service Error: $e");
  }

  // ✅ ONBOARDING CHECK
  final prefs = await SharedPreferences.getInstance();
  final bool seenOnboarding = prefs.getBool('seen_onboarding') ?? false;

  runApp(MyDriveApp(seenOnboarding: seenOnboarding));
}

// 🔔 NOTIFICATION SETUP
Future<void> setupNotifications() async {
  if (Platform.isWindows) return;

  final messaging = FirebaseMessaging.instance;

  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print('User granted permission');

    try {
      String? token = await messaging.getToken();
      print("🔥 FCM Token: $token");

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
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: seenOnboarding ? const AuthGate() : const OnboardingPage(),
    );
  }
}

/// 🔒 AUTH GATE
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = supabase.auth.currentSession;

        if (session == null) {
          return const LoginPage();
        }

        return const VaultLoginPage();
      },
    );
  }
}
