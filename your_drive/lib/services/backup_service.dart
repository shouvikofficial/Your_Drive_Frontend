import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart' as dio;
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cryptography/cryptography.dart';

import '../config/env.dart';
import '../services/vault_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);

    final service = BackupService();
    await service.startAutoBackup();

    return Future.value(true);
  });
}

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> statusNotifier = ValueNotifier("Idle");
  bool _isBackingUp = false;

  Set<String> _serverHashes = {};
  bool _hasSyncedWithServer = false;

  Future<void> initBackgroundService() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  Future<void> scheduleBackgroundBackup() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final prefs = await SharedPreferences.getInstance();
    final wifiOnly = prefs.getBool('wifi_only') ?? true;
    final chargingOnly = prefs.getBool('charging_only') ?? false;

    Workmanager().registerPeriodicTask(
      "1",
      "autoBackupTask",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: wifiOnly ? NetworkType.unmetered : NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresCharging: chargingOnly,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  void cancelBackgroundBackup() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    Workmanager().cancelAll();
  }

  Future<bool> requestUniversalPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        await Permission.notification.request();

        return (photos.isGranted || photos.isLimited) &&
            (videos.isGranted || videos.isLimited);
      } else {
        final status = await Permission.storage.request();

        if (androidInfo.version.sdkInt >= 30 && status.isDenied) {
          return await Permission.manageExternalStorage.request().isGranted;
        }

        return status.isGranted;
      }
    }

    return true;
  }

  void stopBackup() {
    _isBackingUp = false;
    statusNotifier.value = "Backup stopped";
  }

  Future<void> startAutoBackup() async {
    if (_isBackingUp) return;

    _isBackingUp = true;
    statusNotifier.value = "Preparing...";

    final prefs = await SharedPreferences.getInstance();
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      _stop("User not logged in");
      return;
    }

    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        _stop("Mobile Only");
        return;
      }

      if (!await requestUniversalPermissions()) {
        _stop("Permission denied");
        return;
      }

      if (!await _checkConstraints(prefs)) {
        _isBackingUp = false;
        return;
      }

      await _syncServerState(user.id);

      statusNotifier.value = "Scanning gallery...";

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );

      if (albums.isEmpty) {
        _stop("No media found");
        return;
      }

      final recentAlbum = albums.first;
      final totalAssets = await recentAlbum.assetCountAsync;

      int currentPage = 0;
      const pageSize = 100;
      int processedCount = 0;

      while (_isBackingUp) {
        final batch = await recentAlbum.getAssetListPaged(page: currentPage, size: pageSize);
        if (batch.isEmpty) break;

        final uploadedList = prefs.getStringList('uploaded_assets') ?? [];
        final uploadedIds = uploadedList.toSet();

        for (final asset in batch) {
          if (!await _checkConstraints(prefs)) {
            _isBackingUp = false;
            return;
          }

          statusNotifier.value = "Syncing ${processedCount + 1} / $totalAssets";
          progressNotifier.value = processedCount / totalAssets;
          processedCount++;

          if (uploadedIds.contains(asset.id)) continue;

          final file = await asset.file;
          if (file == null) continue;

          final fileHash = await _getFileHash(file);

          if (_serverHashes.contains(fileHash)) {
            uploadedIds.add(asset.id);
            await prefs.setStringList('uploaded_assets', uploadedIds.toList());
            continue;
          }

          final success = await _uploadChunkedFile(file, fileHash, file.path);

          if (success) {
            uploadedIds.add(asset.id);
            _serverHashes.add(fileHash);
            await prefs.setStringList('uploaded_assets', uploadedIds.toList());
          }
        }

        currentPage++;
      }

      if (_isBackingUp) {
        statusNotifier.value = "Backup complete";
        progressNotifier.value = 1.0;
      }
    } catch (e) {
      statusNotifier.value = "Error occurred";
      debugPrint("Backup error: $e");
    } finally {
      _isBackingUp = false;
    }
  }

  Future<bool> _checkConstraints(SharedPreferences prefs) async {
    await prefs.reload();

    final enabled = prefs.getBool('backup_enabled') ?? false;
    if (!enabled) {
      statusNotifier.value = "Backup Disabled";
      return false;
    }

    final wifiOnly = prefs.getBool('wifi_only') ?? true;
    if (wifiOnly) {
      final connectivity = await Connectivity().checkConnectivity();
      final hasWifi = connectivity.contains(ConnectivityResult.wifi) ||
          connectivity.contains(ConnectivityResult.ethernet);

      if (!hasWifi) {
        statusNotifier.value = "Waiting for Wi-Fi...";
        return false;
      }
    }

    final chargingOnly = prefs.getBool('charging_only') ?? false;
    if (chargingOnly) {
      final battery = await Battery().batteryState;
      if (battery != BatteryState.charging && battery != BatteryState.full) {
        statusNotifier.value = "Waiting for Charger...";
        return false;
      }
    }

    return true;
  }

  Future<bool> _uploadChunkedFile(File file, String hash, String originalPath) async {
    try {
      final dioClient = dio.Dio();
      final url = "${Env.backendBaseUrl}/api/upload-chunk";

      final name = originalPath.split(Platform.pathSeparator).last;
      final size = await file.length();

      const chunkSize = 5 * 1024 * 1024;
      final totalChunks = (size / chunkSize).ceil();
      final uploadId =
          "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";

      final key = await VaultService().getSecretKey();
      final baseNonce = VaultService().generateNonce();
      final algo = AesGcm.with256bits();

      final raf = await file.open();
      dio.Response? response;

      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = min(start + chunkSize, size);
        final length = end - start;

        await raf.setPosition(start);
        final plainBytes = await raf.read(length);

        final nonce = List<int>.from(baseNonce);
        nonce[8] = (i >> 24) & 0xFF;
        nonce[9] = (i >> 16) & 0xFF;
        nonce[10] = (i >> 8) & 0xFF;
        nonce[11] = i & 0xFF;

        final secretBox = await algo.encrypt(plainBytes, secretKey: key, nonce: nonce);
        final encryptedBytes = secretBox.cipherText + secretBox.mac.bytes;

        int retry = 0;
        bool ok = false;

        while (!ok && retry < 3) {
          try {
            response = await dioClient.post(
              url,
              data: dio.FormData.fromMap({
                "file": dio.MultipartFile.fromBytes(encryptedBytes, filename: name),
                "chunk_index": i,
                "total_chunks": totalChunks,
                "file_name": name,
                "upload_id": uploadId,
              }),
            );
            ok = true;
          } catch (_) {
            retry++;
            await Future.delayed(const Duration(seconds: 2));
          }
        }

        if (!ok) {
          await raf.close();
          return false;
        }
      }

      await raf.close();

      if (response?.statusCode == 200) {
        await _saveToSupabase(
          response!.data,
          name,
          size,
          hash,
          base64Encode(baseNonce),
          chunkSize,
        );
        return true;
      }

      return false;
    } catch (e) {
      debugPrint("Upload error: $e");
      return false;
    }
  }

  Future<void> _saveToSupabase(
    Map data,
    String name,
    int size,
    String hash,
    String? iv,
    int chunkSize,
  ) async {
    await Supabase.instance.client.from('files').insert({
      'user_id': Supabase.instance.client.auth.currentUser!.id,
      'file_id': data['file_id'],
      'message_id': data['message_id'],
      'name': name,
      'type': _getFileType(name),
      'size': size,
      'hash': hash,
      'iv': iv,
      'chunk_size': chunkSize,
      'folder_id': null,
    });
  }

  Future<void> _syncServerState(String userId) async {
    if (_hasSyncedWithServer) return;

    final res = await Supabase.instance.client.from('files').select('hash').eq('user_id', userId);

    _serverHashes = (res as List).map((e) => e['hash'] as String).toSet();
    _hasSyncedWithServer = true;
  }

  Future<String> _getFileHash(File file) async {
    final stream = file.openRead();
    return (await sha256.bind(stream).first).toString();
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) return 'image';
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'aac', 'flac'].contains(ext)) return 'music';

    return 'document';
  }

  void _stop(String msg) {
    _isBackingUp = false;
    statusNotifier.value = msg;
  }
}