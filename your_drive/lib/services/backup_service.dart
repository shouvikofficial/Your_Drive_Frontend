import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:workmanager/workmanager.dart'; // ✅ Import Workmanager
import '../config/env.dart';

// 🛑 TOP-LEVEL FUNCTION (Must be outside the class)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("🌙 Background Backup Started");

    // 1. Initialize Supabase (Because background isolate is separate)
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );

    // 2. Run the Backup Logic
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

  // ---------------------------------------------------------
  // ✅ NEW: BACKGROUND SERVICE SETUP (SAFE FOR WINDOWS)
  // ---------------------------------------------------------

  /// 1️⃣ Initialize Workmanager (Call this in main.dart)
  Future<void> initBackgroundService() async {
    // 🛑 FIX: Stop Crash on Windows/Linux/Mac
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint("⚠️ Background Service skipped (Not supported on Desktop)");
      return; 
    }

    await Workmanager().initialize(
      callbackDispatcher, // The top-level function above
      isInDebugMode: false, // Set 'true' to see console logs for testing
    );
  }

  /// 2️⃣ Schedule the 15-Minute Task
  void scheduleBackgroundBackup() {
    // 🛑 FIX: Stop Crash on Windows
    if (!Platform.isAndroid && !Platform.isIOS) return;

    Workmanager().registerPeriodicTask(
      "1", // Unique Name
      "autoBackupTask", // Task Name
      frequency: const Duration(minutes: 15), // Run every 15 mins
      constraints: Constraints(
        networkType: NetworkType.connected, // Only run if online
        requiresBatteryNotLow: true, 
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,

    );
  }

  /// 3️⃣ Cancel Background Task (When user turns off backup)
  void cancelBackgroundBackup() {
    // 🛑 FIX: Stop Crash on Windows
    if (!Platform.isAndroid && !Platform.isIOS) return;

    Workmanager().cancelAll();
  }

  // ---------------------------------------------------------
  // 🚀 EXISTING BACKUP LOGIC
  // ---------------------------------------------------------

  void stopBackup() {
    _isBackingUp = false;
    statusNotifier.value = "Backup stopped";
  }

  Future<void> startAutoBackup() async {
    if (_isBackingUp) return;
    _isBackingUp = true;
    statusNotifier.value = "Preparing...";

    try {
      // 🛑 Platform Check
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        statusNotifier.value = "Mobile Only";
        _isBackingUp = false;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      
      bool isEnabled = prefs.getBool('backup_enabled') ?? false;
      if (!isEnabled) {
        statusNotifier.value = "Backup Disabled";
        _isBackingUp = false;
        return;
      }

      // Wi-Fi Check
      bool wifiOnly = prefs.getBool('wifi_only') ?? true;
      if (wifiOnly) {
        var connectivityResult = await Connectivity().checkConnectivity();
        if (connectivityResult != ConnectivityResult.wifi && 
            connectivityResult != ConnectivityResult.ethernet) {
          statusNotifier.value = "Waiting for Wi-Fi...";
          _isBackingUp = false;
          return;
        }
      }

      // Charging Check
      bool chargingOnly = prefs.getBool('charging_only') ?? false;
      if (chargingOnly) {
        var batteryState = await Battery().batteryState;
        if (batteryState != BatteryState.charging && 
            batteryState != BatteryState.full) {
          statusNotifier.value = "Waiting for charger...";
          _isBackingUp = false;
          return;
        }
      }

      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth) {
        statusNotifier.value = "Permission denied";
        _isBackingUp = false;
        return;
      }

      statusNotifier.value = "Scanning...";

      final FilterOptionGroup filterOption = FilterOptionGroup(
        orders: [
          const OrderOption(
            type: OrderOptionType.createDate,
            asc: false, // Newest First
          ),
        ],
      );

      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        filterOption: filterOption,
      );

      if (albums.isEmpty) {
        _isBackingUp = false;
        statusNotifier.value = "No media found";
        return;
      }

      final int totalAssets = await albums[0].assetCountAsync;
      final List<AssetEntity> media = await albums[0].getAssetListRange(
        start: 0, 
        end: totalAssets, 
      );

      final List<String> uploadedList = prefs.getStringList('uploaded_assets') ?? [];
      final Set<String> uploadedIds = uploadedList.toSet();
      
      List<AssetEntity> toUpload = media.where((asset) => !uploadedIds.contains(asset.id)).toList();

      if (toUpload.isEmpty) {
        statusNotifier.value = "All synced";
        progressNotifier.value = 1.0;
        _isBackingUp = false;
        return;
      }

      int total = toUpload.length;
      int current = 0;

      for (var asset in toUpload) {
        // Live Check: Stopped?
        await prefs.reload();
        bool isEnabled = prefs.getBool('backup_enabled') ?? false;
        
        if (!_isBackingUp || !isEnabled) {
          statusNotifier.value = "Backup stopped";
          _isBackingUp = false;
          break;
        }

        // Live Check: Wi-Fi?
        bool wifiOnly = prefs.getBool('wifi_only') ?? true;
        if (wifiOnly) {
           var connectivity = await Connectivity().checkConnectivity();
           if (connectivity != ConnectivityResult.wifi && 
               connectivity != ConnectivityResult.ethernet) {
             statusNotifier.value = "Paused (No Wi-Fi)";
             _isBackingUp = false;
             break;
           }
        }

        // Live Check: Charging?
        bool chargingOnly = prefs.getBool('charging_only') ?? false;
        if (chargingOnly) {
          var batteryState = await Battery().batteryState;
          if (batteryState != BatteryState.charging && 
              batteryState != BatteryState.full) {
            statusNotifier.value = "Paused (Waiting for charger)";
            _isBackingUp = false;
            break;
          }
        }

        statusNotifier.value = "Syncing ${current + 1}/$total";
        progressNotifier.value = current / total;

        File? file = await asset.file;
        if (file != null) {
          String type = asset.type == AssetType.video ? 'video' : 'image';
          bool success = await _uploadSingleFile(file, type);
          
          if (success) {
            uploadedIds.add(asset.id);
            await prefs.setStringList('uploaded_assets', uploadedIds.toList());
          } else {
            debugPrint("❌ Failed: ${asset.title}");
          }
        }
        current++;
        await Future.delayed(const Duration(seconds: 1)); 
      }

      if (_isBackingUp && current == total) {
        statusNotifier.value = "Sync complete";
        progressNotifier.value = 1.0;
      }

    } catch (e) {
      debugPrint("Backup Error: $e");
      statusNotifier.value = "Error";
    } finally {
      _isBackingUp = false;
    }
  }

  Future<bool> _uploadSingleFile(File file, String type) async {
    try {
      final uploadUrl = "${Env.backendBaseUrl}/upload";
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final response = await request.send();
      if (response.statusCode != 200) return false;

      final body = await response.stream.bytesToString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      await supabase.from('files').insert({
        'user_id': user.id,
        'file_id': decoded['file_id'],
        'thumbnail_id': decoded['thumbnail_id'],
        'message_id': decoded['message_id'],
        'name': file.path.split('/').last,
        'type': type,
        'folder_id': null,
        'size': await file.length(),
      });
      return true;
    } catch (e) {
      debugPrint("Upload failed: $e");
      return false;
    }
  }
}