import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  SecretKey? _cachedSecretKey;

  final _aes = AesGcm.with256bits();

  // ============================================================
  // 🔍 CHECK IF USER HAS PIN (SERVER SIDE)
  // ============================================================
  Future<bool> isVaultSetup() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return false;

    final response = await supabase
        .from('profiles')
        .select('vault_salt')
        .eq('id', user.id)
        .single();

    return response['vault_salt'] != null;
  }

  // ============================================================
  // 🆕 FIRST TIME PIN SETUP
  // ============================================================
  Future<void> setupVault(String pin) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception("User not logged in");
    }

    // 🔐 Generate random salt (16 bytes)
    final salt = _aes.newNonce();

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 150000,
      bits: 256,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );

    // ✅ Save salt to Supabase (IMPORTANT)
    await supabase
        .from('profiles')
        .update({'vault_salt': base64Encode(salt)})
        .eq('id', user.id);

    // Cache key in memory
    _cachedSecretKey = secretKey;
  }

  // ============================================================
  // 🔓 UNLOCK VAULT (ENTER PIN)
  // ============================================================
  Future<bool> unlockVault(String pin) async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return false;

      final response = await supabase
          .from('profiles')
          .select('vault_salt')
          .eq('id', user.id)
          .single();

      final saltBase64 = response['vault_salt'];

      if (saltBase64 == null) return false;

      final salt = base64Decode(saltBase64);

      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 150000,
        bits: 256,
      );

      final derivedKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );

      _cachedSecretKey = derivedKey;
      return true;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // 🔐 GET SECRET KEY (FOR ENCRYPTION / DECRYPTION)
  // ============================================================
  Future<SecretKey> getSecretKey() async {
    if (_cachedSecretKey == null) {
      throw Exception("Vault locked. Please enter PIN.");
    }
    return _cachedSecretKey!;
  }

  // ============================================================
  // 🔁 GENERATE NONCE (AES-GCM 12 BYTES)
  // ============================================================
  List<int> generateNonce() {
    return _aes.newNonce();
  }

  // ============================================================
  // 🔒 LOCK VAULT (ON LOGOUT)
  // ============================================================
  void lockVault() {
    _cachedSecretKey = null;
  }
}