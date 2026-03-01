import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  SecretKey? _cachedSecretKey;

  final _aes = AesGcm.with256bits();
  final _secureStorage = const FlutterSecureStorage();

  // ============================================================
  // 🔍 CHECK IF USER HAS PIN (WITH LOCAL CACHE)
  // ============================================================
  Future<bool> isVaultSetup() async {
    // Check local cache first
    final localSalt = await _secureStorage.read(key: 'vault_salt');
    if (localSalt != null) return true;

    // Try fetching from server
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return false;

      final response = await supabase
          .from('profiles')
          .select('vault_salt')
          .eq('id', user.id)
          .single();

      final salt = response['vault_salt'];
      if (salt != null) {
        // Cache salt locally for offline use
        await _secureStorage.write(key: 'vault_salt', value: salt);
        return true;
      }
      return false;
    } catch (e) {
      // Offline — no local salt means vault not setup
      return false;
    }
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

    final saltBase64 = base64Encode(salt);

    // ✅ Save salt to Supabase
    await supabase
        .from('profiles')
        .update({'vault_salt': saltBase64})
        .eq('id', user.id);

    // ✅ Cache salt locally for offline unlock
    await _secureStorage.write(key: 'vault_salt', value: saltBase64);

    // Cache key in memory
    _cachedSecretKey = secretKey;
  }

  // ============================================================
  // 🔓 UNLOCK VAULT (ENTER PIN — WORKS OFFLINE)
  // ============================================================
  Future<bool> unlockVault(String pin) async {
    String? saltBase64;

    // 1️⃣ Try local cache first
    saltBase64 = await _secureStorage.read(key: 'vault_salt');

    // 2️⃣ If not cached, try fetching from server
    if (saltBase64 == null) {
      try {
        final supabase = Supabase.instance.client;
        final user = supabase.auth.currentUser;

        if (user == null) return false;

        final response = await supabase
            .from('profiles')
            .select('vault_salt')
            .eq('id', user.id)
            .single();

        saltBase64 = response['vault_salt'] as String?;

        if (saltBase64 != null) {
          // Cache for next time
          await _secureStorage.write(key: 'vault_salt', value: saltBase64);
        }
      } catch (_) {
        // No internet & no local cache — can't unlock
        return false;
      }
    }

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