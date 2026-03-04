import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import 'package:path_provider/path_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive/hive.dart';

import '../config/env.dart';
import '../services/vault_service.dart';
import '../services/network_speed.dart';
import '../services/upload_strategy.dart';
import '../services/retry_helper.dart';
import '../services/resume_store.dart';
import '../workers/encryption_worker.dart';
import '../workers/hash_worker.dart';
import '../workers/media_thumbnail_worker.dart';

// ════════════════════════════════════════════════════════════
// TOP-LEVEL WORKMANAGER CALLBACK
// ════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("WorkManager backup trigger fired");

    try {
      WidgetsFlutterBinding.ensureInitialized();

      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
      if (!Hive.isBoxOpen('uploads')) {
        await Hive.openBox('uploads');
      }

      await Supabase.initialize(
        url: Env.supabaseUrl,
        anonKey: Env.supabaseAnonKey,
      );

      final service = BackupService();
      await service._executeBackup();
    } catch (e) {
      debugPrint("WorkManager error: $e");
    }

    return true;
  });
}

// ════════════════════════════════════════════════════════════
// FOREGROUND TASK HANDLER  (runs in its own isolate after
// the app is closed — this is what keeps backup alive)
// ════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
class BackupTaskHandler extends TaskHandler {
  bool _initialized = false;

  /// Ensure all dependencies are ready (may be a fresh isolate)
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      WidgetsFlutterBinding.ensureInitialized();

      final dir = await getApplicationDocumentsDirectory();
      Hive.init(dir.path);
      if (!Hive.isBoxOpen('uploads')) {
        await Hive.openBox('uploads');
      }

      try {
        await Supabase.initialize(
          url: Env.supabaseUrl,
          anonKey: Env.supabaseAnonKey,
        );
      } catch (_) {
        // Already initialized (app still alive in same isolate)
      }

      _initialized = true;
      debugPrint("[BackupTaskHandler] Initialized successfully");
    } catch (e) {
      debugPrint("[BackupTaskHandler] Init error: $e");
    }
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint("[BackupTaskHandler] onStart (starter=$starter)");
    await _ensureInitialized();

    // Run backup immediately when the foreground service starts
    final service = BackupService();
    await service._executeBackup();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    debugPrint("[BackupTaskHandler] onRepeatEvent fired");
    _periodicBackup();
  }

  /// Periodic check: re-run backup if enabled and not already running
  Future<void> _periodicBackup() async {
    await _ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final enabled = prefs.getBool('backup_enabled') ?? false;
    if (!enabled) {
      debugPrint("[BackupTaskHandler] Backup disabled — stopping service");
      await FlutterForegroundTask.stopService();
      return;
    }

    final service = BackupService();
    if (!service._isBackingUp) {
      await service._executeBackup();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint("[BackupTaskHandler] onDestroy");
  }
}

// ════════════════════════════════════════════════════════════
// BACKUP PHASE ENUM (for UI binding)
// ════════════════════════════════════════════════════════════
enum BackupPhase {
  idle,
  scanning,
  uploading,
  complete,
  error,
  waitingWifi,
  waitingCharger,
}

// ════════════════════════════════════════════════════════════
// FOREGROUND TASK ENTRY POINT
// ════════════════════════════════════════════════════════════
@pragma('vm:entry-point')
void _foregroundTaskStart() {
  FlutterForegroundTask.setTaskHandler(BackupTaskHandler());
}

// ════════════════════════════════════════════════════════════
//  BACKUP SERVICE  (Production-Grade)
//
//  Upload Engine (same as UploadManager):
//   - Per-chunk AES-256-GCM encryption in isolate
//   - Adaptive chunk sizes (UploadStrategy)
//   - Resume support (ResumeStore / Hive)
//   - Retry with exponential backoff
//   - Thumbnail generation + encrypted upload
//   - Hash deduplication
//
//  Smart Scheduling (Google Drive / Proton Drive style):
//   - Delta sync — only scans photos newer than last backup
//   - Exponential backoff when nothing to upload
//   - Foreground service while backup is active
//   - Auto-resume on connectivity / charger change
//   - Periodic WorkManager fallback (Android 15-min min)
// ════════════════════════════════════════════════════════════
class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  // ───── UI Observables ─────
  final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> statusNotifier = ValueNotifier("Idle");
  final ValueNotifier<BackupPhase> phaseNotifier =
      ValueNotifier(BackupPhase.idle);

  // ───── Internal State ─────
  bool _isBackingUp = false;
  bool get isBackingUp => _isBackingUp;

  Set<String> _serverHashes = {};
  bool _hasSyncedWithServer = false;

  // ───── Smart Scheduler State ─────
  StreamSubscription? _connectivitySub;
  StreamSubscription? _batterySub;
  Timer? _schedulerTimer;
  int _consecutiveIdleRuns = 0;
  static const int _maxBackoffMinutes = 60; // cap backoff at 1 hour
  static const int _baseIntervalSeconds = 30; // initial poll after first run

  // ───── Upload Engine Constants ─────
  static const int _maxActiveChunks = 6;
  int _activeChunks = 0;
  DateTime _lastUiUpdate = DateTime.now();

  final String _chunkUploadUrl = "${Env.backendBaseUrl}/api/upload-chunk";

  // ═══════════════════════════════════════════════════
  //  1.  INIT & SCHEDULING
  // ═══════════════════════════════════════════════════

  /// Call once at app startup (main.dart)
  Future<void> initBackgroundService() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // WorkManager init
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

    // Foreground task init
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'backup_channel',
        channelName: 'Cloud Guard Backup',
        channelDescription: 'Backing up your photos & videos',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        eventAction: ForegroundTaskEventAction.repeat(
          5 * 60 * 1000, // 5 minutes in milliseconds
        ),
      ),
    );
  }

  /// Register the 15-min WorkManager periodic task (Android minimum)
  Future<void> scheduleBackgroundBackup() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final prefs = await SharedPreferences.getInstance();
    final wifiOnly = prefs.getBool('wifi_only') ?? true;
    final chargingOnly = prefs.getBool('charging_only') ?? false;

    Workmanager().registerPeriodicTask(
      "backup_periodic",
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
    _stopScheduler();
  }

  // ─────────────────────────────────────────────────
  //  SMART SCHEDULER  (Google/Proton Drive style)
  //
  //  - Monitors connectivity + battery in real-time
  //  - Re-triggers backup whenever conditions are met
  //  - Exponential backoff when nothing new to upload
  //  - Immediate re-trigger on Wi-Fi connect / charger plug
  // ─────────────────────────────────────────────────

  /// Start the smart scheduler — call when user enables backup
  void startScheduler() {
    _stopScheduler(); // clean up any existing listeners

    // Auto-resume on connectivity change
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      debugPrint("Connectivity changed: $results");
      _evaluateAndTrigger();
    });

    // Auto-resume on charger plug-in
    _batterySub = Battery().onBatteryStateChanged.listen((state) {
      debugPrint("Battery state: $state");
      _evaluateAndTrigger();
    });

    // Kick off first evaluation
    _evaluateAndTrigger();
  }

  void _stopScheduler() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _batterySub?.cancel();
    _batterySub = null;
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
  }

  /// Evaluate constraints and trigger backup if conditions allow
  Future<void> _evaluateAndTrigger() async {
    debugPrint("[Backup] _evaluateAndTrigger called, _isBackingUp=$_isBackingUp");
    if (_isBackingUp) return; // already running

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('backup_enabled') ?? false;
    if (!enabled) {
      debugPrint("[Backup] Skipped: backup not enabled");
      return;
    }

    final constraintsPassed = await _checkConstraints(prefs);
    debugPrint("[Backup] Constraints passed: $constraintsPassed");
    if (!constraintsPassed) return;

    // Conditions met — trigger
    _runBackupCycle();
  }

  /// Run a single backup cycle, then schedule next evaluation
  Future<void> _runBackupCycle() async {
    if (_isBackingUp) return;

    final uploadedAny = await _executeBackup();

    if (uploadedAny) {
      _consecutiveIdleRuns = 0;
      // Something was uploaded — re-run soon to check for more
      _scheduleNextEvaluation(const Duration(seconds: 10));
    } else {
      _consecutiveIdleRuns++;
      // Nothing to upload — exponential backoff
      final backoffSeconds = min(
        _baseIntervalSeconds * pow(2, _consecutiveIdleRuns).toInt(),
        _maxBackoffMinutes * 60,
      );
      debugPrint("Backup idle, next check in ${backoffSeconds}s");
      _scheduleNextEvaluation(Duration(seconds: backoffSeconds));
    }
  }

  void _scheduleNextEvaluation(Duration delay) {
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer(delay, () => _evaluateAndTrigger());
  }

  // ═══════════════════════════════════════════════════
  //  2.  PERMISSIONS
  // ═══════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════
  //  3.  MAIN BACKUP ENTRY (public)
  // ═══════════════════════════════════════════════════

  void stopBackup() {
    _isBackingUp = false;
    _stopScheduler();
    _stopForegroundService();
    statusNotifier.value = "Backup stopped";
    phaseNotifier.value = BackupPhase.idle;
  }

  /// Public entry — starts persistent foreground service + scheduler
  Future<void> startAutoBackup() async {
    debugPrint("[Backup] startAutoBackup called, _isBackingUp=$_isBackingUp");
    if (_isBackingUp) return;

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('backup_enabled') ?? false;
    debugPrint("[Backup] backup_enabled=$enabled");
    if (!enabled) {
      statusNotifier.value = "Backup Disabled";
      return;
    }

    // Start persistent foreground service (survives app close)
    await _startForegroundService();

    // Register WorkManager as a safety-net (restarts if OS kills service)
    await scheduleBackgroundBackup();

    // In-app scheduler for faster responsiveness while app is open
    startScheduler();
  }

  // ═══════════════════════════════════════════════════
  //  4.  CORE BACKUP ENGINE  (same as UploadManager)
  // ═══════════════════════════════════════════════════

  /// Returns `true` if at least one file was uploaded
  Future<bool> _executeBackup() async {
    if (_isBackingUp) return false;
    _isBackingUp = true;

    statusNotifier.value = "Preparing...";
    phaseNotifier.value = BackupPhase.scanning;
    int uploadedCount = 0;

    final prefs = await SharedPreferences.getInstance();

    // ── ONE-TIME MIGRATION: Clear stale data from old backup code ──
    final migrated = prefs.getBool('backup_v2_migrated') ?? false;
    if (!migrated) {
      debugPrint("[Backup] First run of v2 — clearing stale backup cache");
      await prefs.remove('uploaded_assets');
      await prefs.remove('last_backup_timestamp');
      await prefs.setBool('backup_v2_migrated', true);
      _serverHashes.clear();
      _hasSyncedWithServer = false;
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      debugPrint("[Backup] No user logged in");
      _finish("User not logged in");
      return false;
    }

    debugPrint("[Backup] _executeBackup running for user ${user.id}");

    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        _finish("Mobile Only");
        return false;
      }

      if (!await requestUniversalPermissions()) {
        debugPrint("[Backup] Permission denied");
        _finish("Permission denied");
        return false;
      }

      if (!await _checkConstraints(prefs)) {
        debugPrint("[Backup] Constraints failed in _executeBackup");
        _isBackingUp = false;
        return false;
      }

      // Sync server hashes (once per session)
      await _syncServerState(user.id);

      statusNotifier.value = "Scanning gallery...";
      phaseNotifier.value = BackupPhase.scanning;

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );

      if (albums.isEmpty) {
        _finish("No media found");
        return false;
      }

      final recentAlbum = albums[0];
      final totalAssets = await recentAlbum.assetCountAsync;

      // ── DELTA SYNC: Skip already-processed assets ──
      final lastBackupTimestamp = prefs.getInt('last_backup_timestamp') ?? 0;
      final lastBackupDate =
          DateTime.fromMillisecondsSinceEpoch(lastBackupTimestamp);

      debugPrint("[Backup] totalAssets=$totalAssets, lastBackupTimestamp=$lastBackupTimestamp");
      debugPrint("[Backup] lastBackupDate=$lastBackupDate");

      // Pagination
      int currentPage = 0;
      const pageSize = 80;
      int scannedCount = 0;
      bool reachedOldFiles = false;

      // Skip counters (for diagnostics)
      int skipCached = 0;
      int skipDelta = 0;
      int skipDedup = 0;
      int skipNullFile = 0;
      int skipUploadFail = 0;

      // Load local skip-list
      Set<String> uploadedIds =
          (prefs.getStringList('uploaded_assets') ?? []).toSet();
      debugPrint("[Backup] uploadedIds cached: ${uploadedIds.length}");
      debugPrint("[Backup] serverHashes: ${_serverHashes.length}");

      // Encryption key
      SecretKey? key;
      List<int>? keyBytes;
      try {
        key = await VaultService().getSecretKey();
        keyBytes = await key.extractBytes();
        debugPrint("[Backup] Vault unlocked, key ready");
      } catch (e) {
        debugPrint("[Backup] Vault locked: $e");
        _finish("Vault locked");
        return false;
      }

      phaseNotifier.value = BackupPhase.uploading;

      bool scanCompleted = false;

      while (_isBackingUp && !reachedOldFiles) {
        final batch = await recentAlbum.getAssetListPaged(
          page: currentPage,
          size: pageSize,
        );
        if (batch.isEmpty) {
          scanCompleted = true;
          break;
        }

        for (final asset in batch) {
          if (!_isBackingUp) break;

          // Constraint live-check (every 10 files, not every file — too slow)
          if (scannedCount % 10 == 0) {
            if (!await _checkConstraints(prefs)) {
              debugPrint("[Backup] Constraints no longer met at file $scannedCount — pausing");
              _isBackingUp = false;
              return uploadedCount > 0;
            }
          }

          scannedCount++;
          progressNotifier.value = scannedCount / totalAssets;

          // FAST SKIP: already in local cache
          if (uploadedIds.contains(asset.id)) {
            skipCached++;
            continue;
          }

          // DELTA SKIP: older than last SUCCESSFUL backup run
          if (lastBackupTimestamp > 0 &&
              asset.createDateTime.isBefore(lastBackupDate)) {
            skipDelta++;
            reachedOldFiles = true;
            debugPrint("[Backup] Delta skip: asset ${asset.id} created ${asset.createDateTime} < $lastBackupDate");
            break;
          }

          statusNotifier.value = "Syncing $scannedCount / $totalAssets";

          final file = await asset.file;
          if (file == null) {
            skipNullFile++;
            debugPrint("[Backup] Null file: asset ${asset.id}");
            continue;
          }

          debugPrint("[Backup] Processing: ${file.path} (${asset.createDateTime})");

          // ── HASH (Isolate) ──
          final fileHash = await compute(hashFileInIsolate, file.path);

          if (_serverHashes.contains(fileHash)) {
            // Dedup — file already on server (e.g. from manual upload)
            skipDedup++;
            debugPrint("[Backup] Dedup skip: $fileHash already on server");
            uploadedIds.add(asset.id);
            await prefs.setStringList(
                'uploaded_assets', uploadedIds.toList());
            continue;
          }

          // ── UPLOAD ──
          debugPrint("[Backup] Uploading: ${file.path} hash=$fileHash");

          final success = await _uploadFileChunked(
            file: file,
            fileHash: fileHash,
            key: key,
            keyBytes: keyBytes!,
          );
          debugPrint("[Backup] Upload result: $success");

          if (success) {
            uploadedCount++;
            uploadedIds.add(asset.id);
            _serverHashes.add(fileHash);
            await prefs.setStringList(
                'uploaded_assets', uploadedIds.toList());

            _updateForegroundNotification(
                "Backed up $uploadedCount files...");
          } else {
            skipUploadFail++;
            debugPrint("[Backup] Upload FAILED for: ${file.path}");
          }
        }

        currentPage++;
      }

      // DIAGNOSTICS SUMMARY
      debugPrint("[Backup] ══════════════════════════════════");
      debugPrint("[Backup] Scan complete.");
      debugPrint("[Backup]   Scanned:      $scannedCount");
      debugPrint("[Backup]   Uploaded:      $uploadedCount");
      debugPrint("[Backup]   Skip (cached): $skipCached");
      debugPrint("[Backup]   Skip (delta):  $skipDelta");
      debugPrint("[Backup]   Skip (dedup):  $skipDedup");
      debugPrint("[Backup]   Skip (null):   $skipNullFile");
      debugPrint("[Backup]   Skip (fail):   $skipUploadFail");
      debugPrint("[Backup] ══════════════════════════════════");

      // Record timestamp for delta sync — ONLY when the FULL scan completed.
      // If the scan was interrupted (constraint failure, app killed, etc.)
      // we must NOT save the timestamp, because older files may not have
      // been reached yet. The uploadedIds cache still ensures already-
      // processed files are fast-skipped on the next run.
      if (scanCompleted) {
        await prefs.setInt(
          'last_backup_timestamp',
          DateTime.now().millisecondsSinceEpoch,
        );
        debugPrint("[Backup] Full scan completed — saved delta timestamp");
      } else {
        debugPrint("[Backup] Scan incomplete — NOT saving delta timestamp");
      }

      if (_isBackingUp) {
        if (uploadedCount > 0) {
          statusNotifier.value = "Backed up $uploadedCount files";
        } else if (skipCached > 0 || skipDedup > 0) {
          statusNotifier.value = "Everything up to date";
        } else if (skipNullFile == scannedCount) {
          statusNotifier.value = "No accessible media files";
        } else if (skipUploadFail > 0) {
          statusNotifier.value = "Upload failed for $skipUploadFail files";
        } else {
          statusNotifier.value = "Everything up to date";
        }
        progressNotifier.value = 1.0;
        phaseNotifier.value = BackupPhase.complete;
      }
    } catch (e, stack) {
      debugPrint("[Backup] Error: $e");
      debugPrint("[Backup] Stack: $stack");
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socket') || errStr.contains('host lookup') ||
          errStr.contains('connection') || errStr.contains('network')) {
        statusNotifier.value = "Waiting for internet…";
        phaseNotifier.value = BackupPhase.waitingWifi;
      } else {
        statusNotifier.value = "Error: $e";
        phaseNotifier.value = BackupPhase.error;
      }
    } finally {
      _isBackingUp = false;
    }

    return uploadedCount > 0;
  }

  // ═══════════════════════════════════════════════════
  //  5.  CHUNKED UPLOAD ENGINE  (mirrors UploadManager)
  // ═══════════════════════════════════════════════════

  Future<bool> _uploadFileChunked({
    required File file,
    required String fileHash,
    required SecretKey key,
    required List<int> keyBytes,
  }) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = await file.length();
      if (fileSize == 0) {
        debugPrint("[Backup-Upload] File is empty: $fileName");
        return false;
      }

      debugPrint("[Backup-Upload] Starting: $fileName (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)");

      // Start thumbnail in parallel
      Future<Uint8List?>? thumbnailFuture;
      final fileType = _getFileType(fileName);
      if (fileType == 'image') {
        thumbnailFuture = generateImageThumbnail(file.path);
      } else if (fileType == 'video') {
        thumbnailFuture = generateVideoThumbnail(file.path);
      }

      // ── Strategy ──
      final isWifi = await NetworkSpeed.isWifi();
      final strategy = UploadStrategy.decide(
        fileSize: fileSize,
        isWifi: isWifi,
      );

      // ── Nonce ──
      final baseNonce = VaultService().generateNonce();

      // ── Resume ──
      final uploadId =
          "${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}";
      int uploadedChunks = ResumeStore.getProgress(uploadId);

      // ── Chunk math ──
      final chunkSize = strategy.chunkSize;
      final maxParallel = strategy.parallelChunks;
      final totalChunks = (fileSize / chunkSize).ceil();

      debugPrint("[Backup-Upload] Strategy: chunk=${chunkSize ~/ 1024}KB, parallel=$maxParallel, totalChunks=$totalChunks");
      debugPrint("[Backup-Upload] uploadId=$uploadId, resumeFrom=$uploadedChunks");

      final raf = await file.open();
      String? realMessageIdGlobal;

      Future<void> processChunk(int index) async {
        if (!_isBackingUp) return;

        // RAM gate
        while (_activeChunks >= _maxActiveChunks) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        _activeChunks++;

        try {
          final start = index * chunkSize;
          final end = min(start + chunkSize, fileSize);
          final length = end - start;

          await raf.setPosition(start);
          final plainBytes = await raf.read(length);

          final nonce = _buildChunkNonce(baseNonce, index);

          // Encrypt in isolate
          final encryptedBytes = await compute(
            encryptChunkInIsolate,
            EncryptParams(
              bytes: plainBytes,
              keyBytes: keyBytes,
              nonce: nonce,
            ),
          );

          // Upload with retry
          final response = await RetryHelper.retry(() => dio.Dio().post(
                _chunkUploadUrl,
                data: dio.FormData.fromMap({
                  "file": dio.MultipartFile.fromBytes(
                    encryptedBytes,
                    filename: fileName,
                  ),
                  "chunk_index": index,
                  "total_chunks": totalChunks,
                  "file_name": fileName,
                  "upload_id": uploadId,
                }),
              ));

          if (response.statusCode == null || response.statusCode! >= 300) {
            throw Exception("Chunk $index upload failed");
          }

          // Last chunk — save metadata
          if (response.data["status"] == "done") {
            final realMessageId = response.data["message_id"];
            if (realMessageId == null) {
              throw Exception("Backend returned no message_id");
            }
            realMessageIdGlobal = realMessageId.toString();

            await _saveToSupabase(
              data: {
                "file_id": uploadId,
                "message_id": realMessageId,
              },
              name: fileName,
              size: fileSize,
              hash: fileHash,
              ivBase64: base64Encode(baseNonce),
              chunkSize: chunkSize,
              totalChunks: totalChunks,
            );
          }

          uploadedChunks++;
          await ResumeStore.saveProgress(uploadId, uploadedChunks);

          // Throttle UI
          final now = DateTime.now();
          if (now.difference(_lastUiUpdate).inMilliseconds > 300 ||
              uploadedChunks == totalChunks) {
            _lastUiUpdate = now;
          }
        } finally {
          _activeChunks--;
        }
      }

      // ── Parallel chunk loop ──
      List<Future> pool = [];
      for (int i = uploadedChunks; i < totalChunks; i++) {
        if (!_isBackingUp) break;

        pool.add(processChunk(i));
        if (pool.length == maxParallel) {
          await Future.wait(pool);
          pool.clear();
        }
      }
      if (pool.isNotEmpty) await Future.wait(pool);

      await raf.close();

      // ── Thumbnail upload ──
      if (thumbnailFuture != null) {
        try {
          final thumbBytes = await thumbnailFuture;
          if (thumbBytes != null) {
            final thumbNonce = VaultService().generateNonce();
            final algo = AesGcm.with256bits();
            final secretBox = await algo.encrypt(
              thumbBytes,
              secretKey: key,
              nonce: thumbNonce,
            );
            final encryptedThumb =
                secretBox.cipherText + secretBox.mac.bytes;

            await _uploadEncryptedThumbnail(
              realMessageIdGlobal ?? uploadId,
              encryptedThumb,
              thumbNonce,
            );
          }
        } catch (e) {
          debugPrint("Backup thumbnail error: $e");
        }
      }

      await ResumeStore.clear(uploadId);
      debugPrint("[Backup-Upload] SUCCESS: $fileName");
      return true;
    } catch (e, stack) {
      debugPrint("[Backup-Upload] FAILED: $e");
      debugPrint("[Backup-Upload] Stack: $stack");
      return false;
    }
  }

  // ═══════════════════════════════════════════════════
  //  6.  SUPABASE METADATA
  // ═══════════════════════════════════════════════════

  Future<void> _saveToSupabase({
    required Map data,
    required String name,
    required int size,
    required String hash,
    required String ivBase64,
    required int chunkSize,
    required int totalChunks,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('files').insert({
      'user_id': user.id,
      'file_id': data['file_id'],
      'message_id': data['message_id'],
      'name': name,
      'type': _getFileType(name),
      'folder_id': null, // backup goes to root
      'size': size,
      'hash': hash,
      'iv': ivBase64,
      'chunk_size': chunkSize,
      'total_chunks': totalChunks,
    });
  }

  Future<void> _uploadEncryptedThumbnail(
    String fileId,
    List<int> encryptedBytes,
    List<int> nonce,
  ) async {
    try {
      final supabase = Supabase.instance.client;

      final response = await dio.Dio().post(
        "${Env.backendBaseUrl}/api/upload-thumbnail",
        data: dio.FormData.fromMap({
          "file": dio.MultipartFile.fromBytes(
            encryptedBytes,
            filename: "thumb_$fileId.enc",
          ),
          "upload_id": fileId,
        }),
      );

      if (response.statusCode == null || response.statusCode! >= 300) return;

      final tgThumbMessageId = response.data["message_id"];
      if (tgThumbMessageId == null) return;

      await supabase.from('files').update({
        'thumbnail_id': tgThumbMessageId,
        'thumbnail_iv': base64Encode(nonce),
      }).eq('message_id', int.tryParse(fileId) ?? fileId);
    } catch (e) {
      debugPrint("Backup thumbnail upload error: $e");
    }
  }

  // ═══════════════════════════════════════════════════
  //  7.  FOREGROUND SERVICE
  // ═══════════════════════════════════════════════════

  Future<void> _startForegroundService() async {
    if (!Platform.isAndroid) return;

    try {
      if (await FlutterForegroundTask.isRunningService) return;

      await FlutterForegroundTask.startService(
        notificationTitle: "Cloud Guard Backup",
        notificationText: "Backing up your photos & videos...",
        callback: _foregroundTaskStart,
      );
    } catch (e) {
      debugPrint("Foreground svc start error: $e");
    }
  }

  void _updateForegroundNotification(String text) {
    if (!Platform.isAndroid) return;
    try {
      FlutterForegroundTask.updateService(
        notificationTitle: "Cloud Guard Backup",
        notificationText: text,
      );
    } catch (_) {}
  }

  Future<void> _stopForegroundService() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════
  //  8.  CONSTRAINT CHECKER
  // ═══════════════════════════════════════════════════

  Future<bool> _checkConstraints(SharedPreferences prefs) async {
    await prefs.reload();

    final isEnabled = prefs.getBool('backup_enabled') ?? false;
    if (!isEnabled) {
      statusNotifier.value = "Backup Disabled";
      phaseNotifier.value = BackupPhase.idle;
      return false;
    }

    // No internet at all?
    final connectivity = await Connectivity().checkConnectivity();
    final hasAnyConnection = connectivity.any((r) => r != ConnectivityResult.none);
    if (!hasAnyConnection) {
      statusNotifier.value = "Waiting for internet…";
      phaseNotifier.value = BackupPhase.waitingWifi;
      return false;
    }

    // Wi-Fi check
    final wifiOnly = prefs.getBool('wifi_only') ?? true;
    if (wifiOnly) {
      final hasWifi = connectivity.contains(ConnectivityResult.wifi) ||
          connectivity.contains(ConnectivityResult.ethernet);
      if (!hasWifi) {
        statusNotifier.value = "Waiting for Wi-Fi…";
        phaseNotifier.value = BackupPhase.waitingWifi;
        return false;
      }
    }

    // Charging check
    final chargingOnly = prefs.getBool('charging_only') ?? false;
    if (chargingOnly) {
      final battery = await Battery().batteryState;
      if (battery != BatteryState.charging && battery != BatteryState.full) {
        statusNotifier.value = "Waiting for Charger...";
        phaseNotifier.value = BackupPhase.waitingCharger;
        return false;
      }
    }

    return true;
  }

  // ═══════════════════════════════════════════════════
  //  9.  HELPERS
  // ═══════════════════════════════════════════════════

  /// Sync file hashes from the server (once per session)
  Future<void> _syncServerState(String userId) async {
    if (_hasSyncedWithServer) return;

    debugPrint("[Backup] Syncing server state for user: $userId");

    // Paginate to fetch ALL hashes (Supabase default limit is 1000)
    final Set<String> allHashes = {};
    int from = 0;
    const pageSize = 1000;

    while (true) {
      final res = await Supabase.instance.client
          .from('files')
          .select('hash')
          .eq('user_id', userId)
          .range(from, from + pageSize - 1);

      final rows = res as List;
      if (rows.isEmpty) break;

      for (final row in rows) {
        final h = row['hash'];
        if (h != null) allHashes.add(h as String);
      }

      if (rows.length < pageSize) break; // last page
      from += pageSize;
    }

    _serverHashes = allHashes;
    _hasSyncedWithServer = true;

    debugPrint("[Backup] Server hashes loaded: ${_serverHashes.length} files already on server");
  }

  /// Deterministic per-chunk nonce derivation
  List<int> _buildChunkNonce(List<int> baseNonce, int index) {
    final nonce = List<int>.from(baseNonce);
    nonce[8] = (index >> 24) & 0xFF;
    nonce[9] = (index >> 16) & 0xFF;
    nonce[10] = (index >> 8) & 0xFF;
    nonce[11] = index & 0xFF;
    return nonce;
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(ext)) {
      return 'image';
    }
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
    if (['mp3', 'wav', 'aac', 'flac', 'm4a'].contains(ext)) return 'music';
    return 'document';
  }

  void _finish(String msg) {
    _isBackingUp = false;
    statusNotifier.value = msg;
    phaseNotifier.value = BackupPhase.idle;
  }

  /// Force a full re-scan (clears delta timestamp)
  Future<void> resetBackupState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_backup_timestamp');
    await prefs.remove('uploaded_assets');
    _serverHashes.clear();
    _hasSyncedWithServer = false;
    _consecutiveIdleRuns = 0;
    statusNotifier.value = "Reset — ready to re-scan";
    phaseNotifier.value = BackupPhase.idle;
  }
}
