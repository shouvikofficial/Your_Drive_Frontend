import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'dart:io'; // ✅ Import this to check for Windows/Android

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// 🔍 Check if device has biometrics
  static Future<bool> hasBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// 🔐 Authenticate User
  static Future<bool> authenticate() async {
    final isAvailable = await hasBiometrics();
    if (!isAvailable) return false;

    try {
      return await _auth.authenticate(
        localizedReason: 'Scan your fingerprint to unlock',
        options: AuthenticationOptions(
          stickyAuth: true,
          // 🛑 FIX: Only use 'biometricOnly' on Android/iOS
          biometricOnly: Platform.isAndroid || Platform.isIOS, 
        ),
      );
    } on PlatformException catch (e) {
      print("Biometric Error: $e");
      return false;
    }
  }
}