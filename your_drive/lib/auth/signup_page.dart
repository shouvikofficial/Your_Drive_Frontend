import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../theme/app_colors.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController name = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();

  bool loading = false;
  String? _currentSessionId;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
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



  // ================= EMAIL SIGNUP =================
  Future<void> signup() async {
    final nameText = name.text.trim();
    final emailText = email.text.trim();
    final passText = password.text.trim();

    if (nameText.isEmpty || emailText.isEmpty || passText.isEmpty) {
      showMsg("All fields are required");
      return;
    }

    setState(() => loading = true);

    try {
      final supabase = Supabase.instance.client;

      final res = await supabase.auth.signUp(
        email: emailText,
        password: passText,
        data: {'full_name': nameText},
      );

      final user = res.user;
      if (user == null) {
        showMsg("Signup failed");
        return;
      }

      // insert profile safely (ignore duplicate)
      await supabase.from('profiles').upsert({
        'id': user.id,
        'name': nameText,
      });
      await _createSession();

      if (!mounted) return;

      showMsg("Account created! Please login.");
      Navigator.pop(context);
    } on AuthException catch (e) {
      showMsg(e.message);
    } catch (e) {
      showMsg("Signup failed. Please try again.");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }
  
  
  // ================= GOOGLE SIGNUP (v6) =================
  Future<void> googleSignup() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      showMsg("Google Signup works only on Android/iOS.");
      return;
    }

    setState(() => loading = true);

    try {
      const webClientId =
          '425409648184-g356qa4l1oqnemgecpn2r8aun64k2rmq.apps.googleusercontent.com';

      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
      );

      // 🛑 FIX: Force account picker by signing out first
      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      // user cancelled
      if (googleUser == null) {
        setState(() => loading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null || idToken == null) {
        throw "Missing Google Auth Token";
      }

      // Sign in / Sign up via Supabase
      final res = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      


      final user = res.user;
      if (user != null) {
        // create profile if not exists
        await Supabase.instance.client.from('profiles').upsert({
          'id': user.id,
          'name': user.userMetadata?['full_name'] ?? 'Google User',
        });
        await _createSession();
      }

      if (!mounted) return;

      Navigator.pop(context);
    } catch (e) {
      showMsg("Google Sign in failed: $e");
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
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            )
                          ],
                        ),
                        child: const Icon(Icons.cloud, size: 38, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Your Drive",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Create your secure account",
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 32),

                      _buildTextField(controller: name, hint: "Full Name", icon: Icons.person_outline),
                      const SizedBox(height: 16),
                      _buildTextField(controller: email, hint: "Email Address", icon: Icons.email_outlined),
                      const SizedBox(height: 16),
                      _buildTextField(controller: password, hint: "Password", icon: Icons.lock_outline, isPassword: true),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: loading ? null : signup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: loading
                              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                              : const Text("Sign Up", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey[400])),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text("or sign up with", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ),
                          Expanded(child: Divider(color: Colors.grey[400])),
                        ],
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: loading ? null : googleSignup,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Colors.black12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text(
                            "Continue with Google",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Already have an account? ", style: TextStyle(color: Colors.grey[600])),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text(
                              "Login",
                              style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
    );
  }
}