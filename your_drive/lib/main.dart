import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ IMPORT Shared Preferences

// ✅ IMPORT SERVICES & PAGES
import 'services/backup_service.dart';
import 'auth/login_page.dart';
import 'ui/dashboard_page.dart';
import 'ui/onboarding_page.dart'; // ✅ IMPORT Onboarding Page

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 1. SUPABASE INIT (MANDATORY)
  await Supabase.initialize(
    url: 'https://knzogkwgczsnfaypokto.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtuem9na3dnY3pzbmZheXBva3RvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMTUzNjEsImV4cCI6MjA4NTc5MTM2MX0.i-aHu3ZcbtN2WPgLl8nvY6m5fhKgeNlwnZt-QMwRQFg',
  );

  // ✅ 2. INITIALIZE BACKGROUND BACKUP SERVICE
  await BackupService().initBackgroundService();

  // ✅ 3. CHECK ONBOARDING STATUS
  final prefs = await SharedPreferences.getInstance();
  final bool seenOnboarding = prefs.getBool('seen_onboarding') ?? false;

  runApp(MyDriveApp(seenOnboarding: seenOnboarding));
}

class MyDriveApp extends StatelessWidget {
  final bool seenOnboarding; // ✅ Receive the flag

  const MyDriveApp({super.key, required this.seenOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Drive',

      // ✅ LIGHT THEME
      theme: ThemeData(
        brightness: Brightness.light,
        useMaterial3: true,
      ),

      // 🔥 LOGIC:
      // If user hasn't seen onboarding -> Show OnboardingPage
      // If user HAS seen it -> Go to AuthGate (Login or Dashboard)
      home: seenOnboarding ? const AuthGate() : const OnboardingPage(),
    );
  }
}

/// ------------------------------------------------------
/// AUTH GATE
/// ------------------------------------------------------
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;

        if (session != null) {
          return const DashboardPage();
        }

        return const LoginPage();
      },
    );
  }
}