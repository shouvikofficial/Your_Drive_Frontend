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
  // 🔍 CHECK IF USER HAS PIN (ONLINE FIRST, THEN LOCAL CACHE)
  // ============================================================
  Future<bool> isVaultSetup() async {
    // Try fetching from server FIRST (if online) to prevent desync
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session != null) {
        // Network calls with timeout
        final profileFuture = supabase
            .from('profiles')
            .select('vault_salt')
            .eq('id', session.user.id)
            .single()
            .timeout(const Duration(seconds: 3));

        final userFuture = supabase.auth.getUser().timeout(const Duration(seconds: 3));

        final results = await Future.wait([profileFuture, userFuture]);
        final response = results[0] as Map<String, dynamic>;
        final userResponse = results[1] as UserResponse;

        final saltBase64 = response['vault_salt'];
        final vaultHashBase64 = userResponse.user?.userMetadata?['vault_hash'];

        if (saltBase64 != null && vaultHashBase64 != null) {
          // Cache locally for offline use
          await _secureStorage.write(key: 'vault_salt', value: saltBase64);
          await _secureStorage.write(key: 'vault_hash', value: vaultHashBase64);
          return true;
        } else if (saltBase64 == null) {
          // Wiped remotely
          await _secureStorage.delete(key: 'vault_salt');
          await _secureStorage.delete(key: 'vault_hash');
          return false;
        }
      }
    } catch (_) {
      // Offline fallback
    }

    // Check local cache fallback
    final localSalt = await _secureStorage.read(key: 'vault_salt');
    final localHash = await _secureStorage.read(key: 'vault_hash');
    if (localSalt != null && localHash != null) return true;

    return false;
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

    // ✅ Compute a SHA-256 hash of the derived key to verify PIN later
    final secretKeyBytes = await secretKey.extractBytes();
    final hashAlgorithm = Sha256();
    final hash = await hashAlgorithm.hash(secretKeyBytes);
    final vaultHashBase64 = base64Encode(hash.bytes);

    final saltBase64 = base64Encode(salt);

    // ✅ Save salt to Supabase profile
    await supabase
        .from('profiles')
        .update({'vault_salt': saltBase64})
        .eq('id', user.id);

    // ✅ Save hash to Supabase auth user metadata
    await supabase.auth.updateUser(
      UserAttributes(data: {'vault_hash': vaultHashBase64}),
    );

    // ✅ Cache salt AND hash locally for offline unlock
    await _secureStorage.write(key: 'vault_salt', value: saltBase64);
    await _secureStorage.write(key: 'vault_hash', value: vaultHashBase64);

    // Cache key in memory
    _cachedSecretKey = secretKey;
  }

  // ============================================================
  // 🔓 UNLOCK VAULT (ENTER PIN — WORKS OFFLINE)
  // ============================================================
  Future<bool> unlockVault(String pin) async {
    String? saltBase64;
    String? vaultHashBase64;

    // 1️⃣ Try fetching from server FIRST
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;

      if (session != null) {
        final profileFuture = supabase
            .from('profiles')
            .select('vault_salt')
            .eq('id', session.user.id)
            .single()
            .timeout(const Duration(seconds: 3));

        final userFuture = supabase.auth.getUser().timeout(const Duration(seconds: 3));

        final results = await Future.wait([profileFuture, userFuture]);
        final response = results[0] as Map<String, dynamic>;
        final userResponse = results[1] as UserResponse;

        saltBase64 = response['vault_salt'] as String?;
        vaultHashBase64 = userResponse.user?.userMetadata?['vault_hash'] as String?;

        if (saltBase64 != null && vaultHashBase64 != null) {
          // Update cache
          await _secureStorage.write(key: 'vault_salt', value: saltBase64);
          await _secureStorage.write(key: 'vault_hash', value: vaultHashBase64);
        } else if (saltBase64 == null) {
           await _secureStorage.delete(key: 'vault_salt');
           await _secureStorage.delete(key: 'vault_hash');
        }
      }
    } catch (_) {
      // Offline fallback
    }

    // 2️⃣ Try local cache if network failed
    saltBase64 ??= await _secureStorage.read(key: 'vault_salt');
    vaultHashBase64 ??= await _secureStorage.read(key: 'vault_hash');

    if (saltBase64 == null || vaultHashBase64 == null) return false;

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

    // 3️⃣ Verify PIN with Hash
    final secretKeyBytes = await derivedKey.extractBytes();
    final hashAlgorithm = Sha256();
    final currentHash = await hashAlgorithm.hash(secretKeyBytes);
    final currentHashBase64 = base64Encode(currentHash.bytes);

    if (currentHashBase64 != vaultHashBase64) {
      return false; // Wrong PIN
    }

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