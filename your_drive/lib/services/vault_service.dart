import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  // 🔐 Hardware secure storage
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  SecretKey? _cachedSecretKey;

  static const _keyName = "vault_key";
  static const _saltName = "vault_salt";

  final _aes = AesGcm.with256bits();

  // ============================================================
  // 1️⃣ CHECK IF VAULT EXISTS
  // ============================================================
  Future<bool> isVaultSetup() async {
    try {
      return await _storage.containsKey(key: _keyName);
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // 2️⃣ SETUP VAULT (FIRST TIME PIN)
  // ============================================================
  Future<void> setupVault(String pin) async {
    try {
      // Generate random salt
      final salt = _aes.newNonce();

      // Derive strong key from PIN using PBKDF2
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );

      final secretKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );

      final keyBytes = await secretKey.extractBytes();

      // Store key + salt securely
      await _storage.write(key: _keyName, value: base64Encode(keyBytes));
      await _storage.write(key: _saltName, value: base64Encode(salt));

      // Cache in memory for current session
      _cachedSecretKey = secretKey;
    } catch (e) {
      throw Exception("Failed to setup vault: $e");
    }
  }

  // ============================================================
  // 3️⃣ UNLOCK VAULT (PIN LOGIN)
  // ============================================================
  Future<bool> unlockVault(String pin) async {
    try {
      final storedKey = await _storage.read(key: _keyName);
      final storedSalt = await _storage.read(key: _saltName);

      if (storedKey == null || storedSalt == null) return false;

      final salt = base64Decode(storedSalt);

      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );

      final derivedKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(pin)),
        nonce: salt,
      );

      final derivedBytes = await derivedKey.extractBytes();

      if (base64Encode(derivedBytes) == storedKey) {
        _cachedSecretKey = derivedKey;
        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // 4️⃣ GET SECRET KEY FOR ENCRYPTION
  // ============================================================
  Future<SecretKey> getSecretKey() async {
    if (_cachedSecretKey != null) return _cachedSecretKey!;

    final storedKey = await _storage.read(key: _keyName);
    if (storedKey == null) {
      throw Exception("Vault locked. Enter PIN.");
    }

    final keyBytes = base64Decode(storedKey);
    _cachedSecretKey = await _aes.newSecretKeyFromBytes(keyBytes);

    return _cachedSecretKey!;
  }

  // ============================================================
  // 5️⃣ GENERATE RANDOM NONCE (12 bytes for AES-GCM)
  // ============================================================
  List<int> generateNonce() {
    return _aes.newNonce();
  }

  // ============================================================
  // 6️⃣ LOCK VAULT (ON LOGOUT / APP CLOSE)
  // ============================================================
  void lockVault() {
    _cachedSecretKey = null;
  }
}
