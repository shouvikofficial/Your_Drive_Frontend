import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart'; // ✅ REQUIRED for ValueNotifier
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
import '../config/env.dart';

// 🛑 TOP-LEVEL FUNCTION
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("🌙 Background Backup Started");

    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );

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

  // 🧠 Memory Cache
  Set<String> _serverHashes = {};
  bool _hasSyncedWithServer = false;

  // ---------------------------------------------------------
  // ✅ 1. BACKGROUND SERVICE SETUP
  // ---------------------------------------------------------
  Future<void> initBackgroundService() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  void scheduleBackgroundBackup() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    Workmanager().registerPeriodicTask(
      "1", "autoBackupTask",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected, requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  void cancelBackgroundBackup() {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    Workmanager().cancelAll();
  }

  // ---------------------------------------------------------
  // ✅ 2. PERMISSIONS
  // ---------------------------------------------------------
  Future<bool> requestUniversalPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        final photos = await Permission.photos.request();
        final videos = await Permission.videos.request();
        final notification = await Permission.notification.request();
        return (photos.isGranted || photos.isLimited) && (videos.isGranted || videos.isLimited);
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

  // ---------------------------------------------------------
  // 🚀 3. OPTIMIZED BACKUP LOGIC (Pagination + Instant Trigger)
  // ---------------------------------------------------------
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

      // 🛑 Pre-flight Permission Check
      if (!await requestUniversalPermissions()) {
        _stop("Permission denied");
        return;
      }
      
      // 🔥 Initial Constraint Check (Instant Pause)
      if (!await _checkConstraints(prefs)) {
        _isBackingUp = false;
        return; 
      }

      // 🔄 Sync Server State
      await _syncServerState(user.id);

      statusNotifier.value = "Scanning gallery...";
      
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        filterOption: FilterOptionGroup(orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)]),
      );

      if (albums.isEmpty) {
        _stop("No media found");
        return;
      }

      final AssetPathEntity recentAlbum = albums[0];
      final int totalAssets = await recentAlbum.assetCountAsync;
      
      // ⚡ PAGINATION SETUP (Infinite Scan)
      int currentPage = 0;
      const int pageSize = 100; // Fetch 100 at a time
      int processedCount = 0;

      // 🔄 THE INFINITE LOOP
      while (_isBackingUp) {
        // Fetch next page of photos
        final List<AssetEntity> batch = await recentAlbum.getAssetListPaged(page: currentPage, size: pageSize);
        
        if (batch.isEmpty) break; // Stop if no more photos

        // Load local cache
        List<String> uploadedList = prefs.getStringList('uploaded_assets') ?? [];
        Set<String> uploadedIds = uploadedList.toSet();

        for (var asset in batch) {
          // 🔥 LIVE PAUSE CHECK (Reacts Instantly)
          if (!await _checkConstraints(prefs)) {
             print("⚠️ Backup paused: Constraints not met.");
             _isBackingUp = false;
             return; 
          }

          // ✅ CLEAN UI UPDATE (Numbers Only)
          statusNotifier.value = "Syncing ${processedCount + 1} / $totalAssets";
          progressNotifier.value = processedCount / totalAssets;
          processedCount++;

          // ⚡ FAST SKIP: Check ID first!
          if (uploadedIds.contains(asset.id)) {
             continue; // Skip without heavy work
          }

          File? file = await asset.file;
          if (file != null) {
            // 🛑 HASH CHECK (Only for new files)
            String fileHash = await _getFileHash(file);

            if (_serverHashes.contains(fileHash)) {
              // Deduplication Skip
              uploadedIds.add(asset.id);
              await prefs.setStringList('uploaded_assets', uploadedIds.toList());
            } else {
              // 🚀 UPLOAD (Status remains "Syncing X / Y")
              bool success = await _uploadChunkedFile(file, fileHash);
              if (success) {
                uploadedIds.add(asset.id);
                _serverHashes.add(fileHash); 
                await prefs.setStringList('uploaded_assets', uploadedIds.toList());
              }
            }
          }
        }
        currentPage++; // Next page
      }

      if (_isBackingUp) {
        statusNotifier.value = "Backup complete";
        progressNotifier.value = 1.0;
      }

    } catch (e) {
      print("Backup Error: $e");
      statusNotifier.value = "Error occurred";
    } finally {
      _isBackingUp = false;
    }
  }

  // ---------------------------------------------------------
  // 🔥 HELPER: INSTANT CONSTRAINT CHECKER
  // ---------------------------------------------------------
  Future<bool> _checkConstraints(SharedPreferences prefs) async {
    await prefs.reload(); // ✅ Catch UI toggles instantly
    
    bool isEnabled = prefs.getBool('backup_enabled') ?? false;
    if (!isEnabled) {
      statusNotifier.value = "Backup Disabled";
      return false;
    }

    bool wifiOnly = prefs.getBool('wifi_only') ?? true;
    if (wifiOnly) {
      final connectivity = await Connectivity().checkConnectivity();
      bool isWifi = connectivity.contains(ConnectivityResult.wifi) || 
                    connectivity.contains(ConnectivityResult.ethernet);
      
      if (!isWifi) {
        statusNotifier.value = "Waiting for Wi-Fi...";
        return false; 
      }
    }

    bool chargingOnly = prefs.getBool('charging_only') ?? false;
    if (chargingOnly) {
      final battery = await Battery().batteryState;
      if (battery != BatteryState.charging && battery != BatteryState.full) {
        statusNotifier.value = "Waiting for Charger...";
        return false; 
      }
    }

    return true; 
  }

  // ---------------------------------------------------------
  // ☁️ SERVER SYNC
  // ---------------------------------------------------------
  Future<void> _syncServerState(String userId) async {
    if (_hasSyncedWithServer) return;
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('files')
          .select('hash')
          .eq('user_id', userId);
      
      if (response != null) {
        _serverHashes = (response as List).map((e) => e['hash'] as String).toSet();
        _hasSyncedWithServer = true;
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------
  // ⬆️ CHUNKED UPLOAD
  // ---------------------------------------------------------
  Future<bool> _uploadChunkedFile(File file, String hash) async {
    try {
      final dioClient = dio.Dio();
      final url = "${Env.backendBaseUrl}/api/upload-chunk";
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = await file.length();
      const chunkSize = 5 * 1024 * 1024;
      final totalChunks = (fileSize / chunkSize).ceil();
      final uploadId = "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";
      final raf = file.openSync();

      dio.Response? response;

      for (int i = 0; i < totalChunks; i++) {
        // 🔥 Instant Pause Check inside chunks
        final prefs = await SharedPreferences.getInstance();
        if (!await _checkConstraints(prefs)) {
          raf.closeSync();
          return false;
        }

        final start = i * chunkSize;
        final end = min(start + chunkSize, fileSize);
        final length = end - start;
        raf.setPositionSync(start);
        final chunkBytes = raf.readSync(length);

        int retry = 0;
        bool chunkSuccess = false;
        while (!chunkSuccess && retry < 3) {
          try {
            response = await dioClient.post(url, data: dio.FormData.fromMap({
              "file": dio.MultipartFile.fromBytes(chunkBytes, filename: fileName),
              "chunk_index": i, "total_chunks": totalChunks, "file_name": fileName, "upload_id": uploadId
            }), options: dio.Options(sendTimeout: const Duration(minutes: 2)));
            chunkSuccess = true;
          } catch (e) {
            retry++;
            await Future.delayed(const Duration(seconds: 2));
          }
        }
        if (!chunkSuccess) { raf.closeSync(); return false; }
      }
      raf.closeSync();

      if (response?.statusCode == 200) {
        await _saveToSupabase(response!.data, fileName, fileSize, hash);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // 🟢 SAVE TO SUPABASE
  Future<bool> _saveToSupabase(Map data, String name, int size, String hash) async {
    try {
       await Supabase.instance.client.from('files').insert({
        'user_id': Supabase.instance.client.auth.currentUser!.id,
        'file_id': data['file_id'],
        'message_id': data['message_id'],
        'name': name,
        'type': _getFileType(name, data['type']), 
        'folder_id': null,
        'size': size,
        'hash': hash
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // 🧠 SMART TYPE DETECTOR
  String _getFileType(String fileName, String? serverType) {
    final ext = fileName.split('.').last.toLowerCase();
    
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp', 'svg'].contains(ext)) return 'image';
    if (['mp4', 'mov', 'avi', 'mkv', 'flv', 'wmv', 'webm', '3gp'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'aac', 'flac', 'm4a', 'ogg', 'wma'].contains(ext)) return 'music';
    if (['apk', 'exe', 'dmg', 'iso', 'msi', 'deb', 'ipa', 'xapk'].contains(ext)) return 'app';
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return 'archive';

    return serverType ?? 'document';
  }

  // 🛠️ HASH HELPER
  Future<String> _getFileHash(File file) async {
    final stream = file.openRead();
    return (await sha256.bind(stream).first).toString();
  }

  void _stop(String msg) {
    _isBackingUp = false;
    statusNotifier.value = msg;
  }
}