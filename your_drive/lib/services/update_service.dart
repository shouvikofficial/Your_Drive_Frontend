import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Checks a remote JSON file for the latest app version.
///
/// JSON format at `https://cloudguardapp.vercel.app/version.json`:
/// ```json
/// {
///   "latest_version": "1.1.0",
///   "min_version": "1.0.0",
///   "download_url": "https://cloudguardapp.vercel.app/",
///   "release_notes": "Bug fixes and performance improvements"
/// }
/// ```
///
/// - current < min_version  → force update (blocks the app)
/// - current < latest_version → optional update (dismissable)
class UpdateService {
  static const String _versionUrl =
      'https://cloudguardapp.vercel.app/version.json';

  /// How often to show the optional prompt (not more than once per day)
  static const String _dismissedKey = 'update_dismissed_at';

  /// Compare two semantic version strings, e.g. "1.2.3" < "1.3.0"
  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList();
    final bParts = b.split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av < bv) return -1;
      if (av > bv) return 1;
    }
    return 0; // equal
  }

  /// Returns update info, or null if up-to-date / check failed.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(_versionUrl))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latestVersion = data['latest_version'] as String;
      final minVersion = data['min_version'] as String;
      final downloadUrl = data['download_url'] as String? ??
          'https://cloudguardapp.vercel.app/';
      final releaseNotes =
          data['release_notes'] as String? ?? 'Bug fixes and improvements';

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      // Current >= latest → up to date
      if (_compareVersions(currentVersion, latestVersion) >= 0) return null;

      // Current < min → force update
      final isForce = _compareVersions(currentVersion, minVersion) < 0;

      // For optional updates, respect the 24h dismiss cooldown
      if (!isForce) {
        final prefs = await SharedPreferences.getInstance();
        final dismissedAt = prefs.getInt(_dismissedKey) ?? 0;
        final hoursSinceDismiss = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(dismissedAt))
            .inHours;
        if (hoursSinceDismiss < 24) return null;
      }

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        releaseNotes: releaseNotes,
        isForceUpdate: isForce,
      );
    } catch (e) {
      debugPrint('[UpdateService] Check failed: $e');
      return null; // fail silently — don't block the app
    }
  }

  /// Mark the optional update as dismissed for 24h cooldown.
  static Future<void> dismissUpdate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _dismissedKey, DateTime.now().millisecondsSinceEpoch);
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final bool isForceUpdate;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isForceUpdate,
  });
}
