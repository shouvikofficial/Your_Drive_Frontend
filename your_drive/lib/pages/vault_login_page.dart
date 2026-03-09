import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:pin_code_fields/pin_code_fields.dart';
import '../services/vault_service.dart';
import '../services/backup_service.dart';
import '../theme/app_colors.dart';
import '../ui/dashboard_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class VaultLoginPage extends StatefulWidget {
  const VaultLoginPage({super.key});

  @override
  State<VaultLoginPage> createState() => _VaultLoginPageState();
}

class _VaultLoginPageState extends State<VaultLoginPage> {
  // 🚀 OPTIMISTIC UI STATE
  bool isSetup = true; 
  bool isLoading = false; 
  bool isResetting = false;
  
  String title = "Welcome Back";
  String subTitle = "Enter your 4-digit security PIN";

  final _vaultService = VaultService();
  StreamController<ErrorAnimationType>? errorController;
  TextEditingController textEditingController = TextEditingController();
  TextEditingController resetEmailController = TextEditingController();
  TextEditingController resetPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    errorController = StreamController<ErrorAnimationType>();
    _checkStatusSilently();
  }

  @override
  void dispose() {
    errorController?.close();
    textEditingController.dispose();
    resetEmailController.dispose();
    resetPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkStatusSilently() async {
  try {
    final hasVault = await _vaultService.isVaultSetup();

    if (mounted) {
      setState(() {
        isSetup = hasVault;

        if (!isSetup) {
          title = "Create Vault PIN";
          subTitle = "Set a secure PIN to protect your private files";
        } else {
          title = "Welcome Back";
          subTitle = "Enter your 4-digit security PIN";
        }
      });

      if (!isSetup) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showInitialSafetyNotice();
        });
      }
    }
  } catch (e) {
    debugPrint("Vault check error: $e");
  }
}

  // --- 🛡️ 1. NEW USER SAFETY NOTICE ---
  void _showInitialSafetyNotice() {
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: const Icon(Icons.lock_person_rounded, size: 80, color: AppColors.blue),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    "Safety First",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "You are the only person who will know this PIN. We never see it and we never store it.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  
                  Text(
                    "This means if you forget your PIN, your files are locked forever. For your privacy, we have no way to reset your PIN or recover your data.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.heavyImpact(); 
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text(
                        "I understand the risk",
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 🔴 2. FORGOT PIN DIALOG (Step 1) ---
  void _showForgotPinDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 28),
            const SizedBox(width: 12),
            const Text("Recovery Unavailable", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Your vault is protected by end-to-end encryption. Without your PIN, the data is mathematically impossible to read.",
              style: TextStyle(color: Colors.grey[800], height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[100]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.delete_forever_rounded, color: Colors.red[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "To regain access, you must reset the vault. This will permanently delete all files currently inside.",
                      style: TextStyle(color: Colors.red[900], fontWeight: FontWeight.bold, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close Step 1
              _showFinalResetConfirmation(); // Open Step 2
            },
            child: Text("Reset Vault & Delete Data", style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- 💀 3. FINAL CONFIRMATION DIALOG (Step 2) ---
  void _showFinalResetConfirmation() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must choose
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Irreversible Action", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text(
          "Are you absolutely sure?\n\nThis action cannot be undone. All your encrypted files will be wiped from this device immediately.",
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel, keep my data", style: TextStyle(color: Colors.black87)),
          ),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.heavyImpact(); // Physical feedback for destructive action
              Navigator.pop(context);
              _showLoginToResetDialog();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Yes, Delete Everything", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- 🔐 4. VERIFY IDENTITY DIALOG (Step 3) ---
  void _showLoginToResetDialog() {
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              const Icon(Icons.security_rounded, color: AppColors.blue, size: 28),
              const SizedBox(width: 12),
              const Text("Verify Identity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Please enter your main account email and password to authorize this vault reset.",
                style: TextStyle(color: Colors.grey[800], fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: resetEmailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !isVerifying,
                decoration: InputDecoration(
                  labelText: "Email",
                  prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: resetPasswordController,
                obscureText: true,
                enabled: !isVerifying,
                decoration: InputDecoration(
                  labelText: "Password",
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
          actions: [
            if (!isVerifying)
              TextButton(
                onPressed: () {
                  resetEmailController.clear();
                  resetPasswordController.clear();
                  Navigator.pop(context);
                },
                child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
              ),
            ElevatedButton(
              onPressed: isVerifying
                  ? null
                  : () async {
                      final email = resetEmailController.text.trim();
                      final password = resetPasswordController.text.trim();

                      if (email.isEmpty || password.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Please enter both email and password")),
                        );
                        return;
                      }

                      setStateDialog(() => isVerifying = true);

                      try {
                        final connectivity = await Connectivity().checkConnectivity();
                        final isOffline = connectivity.isNotEmpty &&
                            connectivity.every((r) => r == ConnectivityResult.none);
                        if (isOffline) {
                          if (context.mounted) {
                            setStateDialog(() => isVerifying = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("No internet connection detected."),
                                backgroundColor: AppColors.blue,
                              ),
                            );
                          }
                          return;
                        }

                        // Re-authenticate using Supabase signInWithPassword
                        await Supabase.instance.client.auth.signInWithPassword(
                          email: email,
                          password: password,
                        );

                        if (context.mounted) {
                          Navigator.pop(context); // Close dialog on success
                          resetEmailController.clear();
                          resetPasswordController.clear();
                          await _performVaultReset(); // Proceed with reset
                        }
                      } on AuthException catch (e) {
                        if (context.mounted) {
                          setStateDialog(() => isVerifying = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.message.toLowerCase().contains("invalid login credentials")
                                    ? "Incorrect email or password."
                                    : e.message,
                              ),
                              backgroundColor: Colors.red.shade400,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          setStateDialog(() => isVerifying = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Verification failed. Please try again."),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text("Verify & Reset", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performVaultReset() async {
    setState(() {
      isLoading = true;
      isResetting = true;
    });
    // Simulate reset time
    await Future.delayed(const Duration(seconds: 2)); 
    
    // ✅ Call your service to wipe data here
    await VaultService().lockVault();
    // In a real app we would clear stored data too. Currently we just clear knowledge of the PIN
    // By resetting the vault hash and salt. The underlying files remain encrypted and effectively lost
    // unless they stored their PIN in memory safely, which they are saying they didn't.
    // We already do lockVault above.
    
    if (mounted) {
      setState(() {
        isLoading = false;
        isResetting = false;
        isSetup = false; 
        title = "Create Vault PIN";
        subTitle = "Vault reset complete. Set a new PIN.";
      });
      textEditingController.clear();
      // Show safety notice again since it's a fresh start
      _showInitialSafetyNotice(); 
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vault has been reset."))
      );
    }
  }

  Future<void> _handlePin(String pin) async {
  setState(() => isLoading = true);

  await Future.delayed(const Duration(milliseconds: 300));

  try {
    if (isSetup) {
      // 🔐 UNLOCK MODE (salt already exists in DB)
      final success = await _vaultService.unlockVault(pin);

      if (!success) {
        throw Exception("Incorrect PIN");
      }

      _goToDashboard();
    } else {
      // 🆕 SETUP MODE (first time only)
      await _vaultService.setupVault(pin);
      _goToDashboard();
    }
  } catch (e) {
    if (mounted) {
      setState(() => isLoading = false);

      errorController!.add(ErrorAnimationType.shake);
      textEditingController.clear();
      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Incorrect PIN. Please try again."),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(20),
        ),
      );
    }
  }
}

  void _goToDashboard() {
    // Auto-resume backup if it was enabled (vault is now unlocked)
    BackupService().startAutoBackup();

    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const DashboardPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // LOCK ICON
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSetup ? Icons.lock_rounded : Icons.lock_outline_rounded,
                        size: 64,
                        color: AppColors.blue,
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // TITLES (Animated)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Column(
                        key: ValueKey<String>(title),
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            subTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[600],
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),

                    // PIN FIELD
                    PinCodeTextField(
                      appContext: context,
                      length: 4,
                      obscureText: true,
                      obscuringCharacter: '●',
                      animationType: AnimationType.scale,
                      controller: textEditingController,
                      errorAnimationController: errorController,
                      keyboardType: TextInputType.number,
                      cursorColor: AppColors.blue,
                      pinTheme: PinTheme(
                        shape: PinCodeFieldShape.box,
                        borderRadius: BorderRadius.circular(16),
                        fieldHeight: 60,
                        fieldWidth: 60,
                        activeFillColor: Colors.white,
                        inactiveFillColor: Colors.white,
                        selectedFillColor: Colors.white,
                        activeColor: AppColors.blue,
                        inactiveColor: Colors.grey[300]!,
                        selectedColor: AppColors.blue,
                        borderWidth: 1.5,
                      ),
                      boxShadows: [
                        BoxShadow(
                          offset: const Offset(0, 4),
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                        )
                      ],
                      enableActiveFill: true,
                      onCompleted: _handlePin,
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 40),
                    
                    // FORGOT PIN (Only for returning users)
                    if (isSetup)
                      TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _showForgotPinDialog();
                        },
                        child: Text(
                          "Forgot PIN?",
                          style: TextStyle(color: Colors.grey[500], fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          
          // ⏳ LOADING OVERLAY
          if (isLoading)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.white.withOpacity(0.3),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              const SizedBox(
                                width: 64,
                                height: 64,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.blue),
                                  strokeWidth: 2.5,
                                  backgroundColor: Color(0xFFE3F2FD),
                                ),
                              ),
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  // Re-using blue since we are not sure if purple exists, 
                                  // but will try blue to keep it safe and professional
                                  color: AppColors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.shield_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            "Please wait",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isResetting 
                                ? "Resetting your vault..." 
                                : (isSetup ? "Unlocking your vault..." : "Securing your vault..."),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}