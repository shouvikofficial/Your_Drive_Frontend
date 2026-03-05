import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
// ADD THIS IMPORT
import 'package:device_info_plus/device_info_plus.dart';
import '../theme/app_colors.dart';
import '../ui/dashboard_page.dart'; 
import '../auth/signup_page.dart';
import '../auth/forgot_password_page.dart'; // ADD THIS IMPORT
import '../services/biometric_service.dart'; 
import '../pages/vault_login_page.dart'; // ✅ IMPORT VAULT PAGE
import 'package:connectivity_plus/connectivity_plus.dart'; // ADD EXPERIMENTAL CONNECTIVITY

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  String? _currentSessionId;

  @override
  void initState() {
    super.initState();
    _checkBiometricAuth(); 
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ================= BIOMETRIC CHECK =================
  Future<void> _checkBiometricAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('biometric_enabled') ?? false;

    // We only auto-login if there is also a Supabase session
    final session = Supabase.instance.client.auth.currentSession;

    if (isEnabled && session != null) {
      bool authenticated = await BiometricService.authenticate();
      
      if (authenticated && mounted) {
        // ✅ GO TO VAULT (User needs to enter PIN to decrypt files)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const VaultLoginPage()),
        );
      }
    }
  }

Future<void> _createSession() async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) return;

  String deviceName = "Unknown Device";

  try {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceName = "${info.brand} ${info.model}";
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceName = info.utsname.machine ?? "iPhone";
    } else if (Platform.isWindows) {
      deviceName = "Windows PC";
    }
  } catch (_) {}

  try {
    /// 1️⃣ Mark old session NOT current
    await supabase
        .from('sessions')
        .update({'is_current': false})
        .eq('user_id', user.id)
        .eq('is_current', true);

    /// 2️⃣ Insert new current session
    final res = await supabase
        .from('sessions')
        .insert({
          'user_id': user.id,
          'device_name': deviceName,
          'last_active': DateTime.now().toIso8601String(),
          'is_current': true,
        })
        .select()
        .single();

    /// 3️⃣ Save current session id locally
    _currentSessionId = res['id'];

  } catch (e) {
    debugPrint("Session create error: $e");
  }
}


  // ================= EMAIL LOGIN =================
  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showMsg("Please enter email and password");
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      showMsg("Please enter a valid email format");
      return;
    }

    setState(() => loading = true);

    try {
      final connectivity = await Connectivity().checkConnectivity();
      final isOffline = connectivity.isNotEmpty && connectivity.every((r) => r == ConnectivityResult.none);
      if (isOffline) {
        showMsg("No internet connection detected.");
        setState(() => loading = false);
        return;
      }

      final supabase = Supabase.instance.client;

      await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      // ✅ create session
      await _createSession();

      if (!mounted) return;

      // ✅ GO TO VAULT (Security Gate)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VaultLoginPage()),
      );
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains("invalid login credentials")) {
        showMsg("Incorrect email or password.");
      } else {
        showMsg(e.message);
      }
    } catch (_) {
      showMsg("An unexpected error occurred. Please try again.");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ================= GOOGLE LOGIN (v6) =================
Future<void> googleLogin() async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    showMsg("Google Login works only on Android/iOS.");
    return;
  }

  setState(() => loading = true);

  try {
    const webClientId =
        '425409648184-g356qa4l1oqnemgecpn2r8aun64k2rmq.apps.googleusercontent.com';

    final GoogleSignIn googleSignIn = GoogleSignIn(
      serverClientId: webClientId,
      scopes: ['email', 'profile'],
    );

    await googleSignIn.signOut();

    final GoogleSignInAccount? googleUser =
        await googleSignIn.signIn();

    if (googleUser == null) {
      setState(() => loading = false);
      return;
    }

    final googleAuth = await googleUser.authentication;

    final accessToken = googleAuth.accessToken;
    final idToken = googleAuth.idToken;

    if (accessToken == null || idToken == null) {
      throw "Missing Google Auth Token";
    }

    final supabase = Supabase.instance.client;

    // 🔐 Sign in (auto creates auth.users if new)
    final res = await supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );

    final user = res.user;
    if (user == null) throw "Login failed";

    // 🔎 Check if profile exists
    final profile = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    // ✅ If profile does not exist → create it
    if (profile == null) {
      await supabase.from('profiles').insert({
        'id': user.id,
        'name': user.userMetadata?['full_name'] ?? 'Google User',
        'email': user.email,
        'avatar_url': googleUser.photoUrl, // ✅ Save Google Avatar
      });
    } else if (profile['avatar_url'] == null && googleUser.photoUrl != null) {
      // ✅ Update avatar if it was previously missing
      await supabase.from('profiles').update({
        'avatar_url': googleUser.photoUrl,
      }).eq('id', user.id);
    }

    // ✅ Create session
    await _createSession();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const VaultLoginPage()),
    );
  } on AuthException catch (e) {
    showMsg(e.message);
  } catch (e) {
    showMsg("Unable to sign in with Google. Please check your connection.");
  } finally {
    if (mounted) setState(() => loading = false);
  }
}

  // ================= SNACKBAR =================
  void showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withOpacity(0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.blue, AppColors.purple],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.blue.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Welcome Back",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Enter your credentials to access your vault",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.3),
                      ),
                      const SizedBox(height: 32),

                      _buildTextField(
                        controller: emailController,
                        hint: "Email Address",
                        icon: Icons.email_outlined,
                      ),
                      const SizedBox(height: 16),

                      _buildTextField(
                        controller: passwordController,
                        hint: "Password",
                        icon: Icons.lock_outline,
                        isPassword: true,
                      ),

                      const SizedBox(height: 12),

                      // FORGOT PASSWORD
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4, top: 4),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (_, __, ___) => const ForgotPasswordPage(),
                                  transitionsBuilder: (_, anim, __, child) =>
                                      FadeTransition(opacity: anim, child: child),
                                  transitionDuration: const Duration(milliseconds: 250),
                                ),
                              );
                            },
                            child: Text(
                              "Forgot Password?",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // LOGIN BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: loading ? null : login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)
                              : const Text(
                                  "Login",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey[400])),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              "or continue with",
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 13),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.grey[400])),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // GOOGLE BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: loading ? null : googleLogin,
                          icon: const Icon(Icons.g_mobiledata_rounded, size: 32, color: Colors.black87),
                          label: const Text(
                            "Continue with Google",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Colors.black12, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Don't have an account? ",
                              style: TextStyle(color: Colors.grey[600])),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SignupPage()),
                              );
                            },
                            child: Text(
                              "Sign Up",
                              style: TextStyle(
                                color: AppColors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================= TEXT FIELD =================
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[500]),
          prefixIcon: Icon(icon, color: Colors.grey[600]),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }
}