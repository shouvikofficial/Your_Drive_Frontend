import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:open_filex/open_filex.dart';

import '../config/env.dart';
import '../services/vault_service.dart';

class FileViewerPage extends StatefulWidget {
  final String messageId;
  final String fileName;
  final String type;

  const FileViewerPage({
    super.key,
    required this.messageId,
    required this.fileName,
    required this.type,
  });

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  bool _isLoading = true;
  String? _error;

  Uint8List? _imageBytes;

  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _tempFile;

  @override
  void initState() {
    super.initState();
    _downloadAndDecrypt();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();

    if (_tempFile != null && _tempFile!.existsSync()) {
      _tempFile!.deleteSync();
    }

    super.dispose();
  }

  // =========================================================
  // DOWNLOAD + DECRYPT
  // =========================================================
  Future<void> _downloadAndDecrypt() async {
    try {
      final supabase = Supabase.instance.client;

      final fileData = await supabase
          .from('files')
          .select('iv')
          .eq('message_id', widget.messageId)
          .maybeSingle();

      if (fileData == null) {
        throw Exception("File metadata not found");
      }

      final String? ivBase64 = fileData['iv'];

      if (ivBase64 == null || ivBase64.isEmpty) {
        throw Exception("Missing encryption IV");
      }

      final nonce = base64Decode(ivBase64);

      final url = "${Env.backendBaseUrl}/api/file/${widget.messageId}";
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception("Failed to download file");
      }

      final secretKey = await VaultService().getSecretKey();
      final algorithm = AesGcm.with256bits();

      final bodyBytes = response.bodyBytes;
      if (bodyBytes.length < 16) throw Exception("Invalid encrypted file");

      final macBytes = bodyBytes.sublist(bodyBytes.length - 16);
      final ciphertext = bodyBytes.sublist(0, bodyBytes.length - 16);

      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes));

      final decryptedBytes =
          await algorithm.decrypt(secretBox, secretKey: secretKey);

      if (!mounted) return;

      // =====================================================
      // TYPE HANDLING
      // =====================================================
      if (_isImage(widget.fileName)) {
        setState(() {
          _imageBytes = Uint8List.fromList(decryptedBytes);
          _isLoading = false;
        });
      } else if (_isVideo(widget.fileName)) {
        await _initializeVideo(decryptedBytes);
      } else {
        await _openDocument(decryptedBytes);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // =========================================================
  // VIDEO PLAYER
  // =========================================================
  Future<void> _initializeVideo(List<int> bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      _tempFile = File("${dir.path}/${widget.fileName}");
      await _tempFile!.writeAsBytes(bytes, flush: true);

      _videoController = VideoPlayerController.file(_tempFile!);
      await _videoController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoController!.value.aspectRatio,
      );

      setState(() => _isLoading = false);
    } catch (_) {
      setState(() {
        _error = "Failed to load video";
        _isLoading = false;
      });
    }
  }

  // =========================================================
  // DOCUMENT OPEN (PDF, DOCX, PPTX, etc.)
  // =========================================================
  Future<void> _openDocument(List<int> bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      _tempFile = File("${dir.path}/${widget.fileName}");
      await _tempFile!.writeAsBytes(bytes, flush: true);

      setState(() => _isLoading = false);

      // 🔥 OPEN IN EXTERNAL APP
      await OpenFilex.open(_tempFile!.path);

      // 🔥 CLOSE THIS SCREEN → no “Preview not available”
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _error = "Failed to open document";
        _isLoading = false;
      });
    }
  }

  // =========================================================
  // TYPE CHECKERS
  // =========================================================
  bool _isImage(String name) =>
      RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|heic)$', caseSensitive: false)
          .hasMatch(name);

  bool _isVideo(String name) =>
      RegExp(r'\.(mp4|mov|avi|mkv|webm)$', caseSensitive: false)
          .hasMatch(name);

  // =========================================================
  // UI
  // =========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(widget.fileName,
            style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : _error != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image,
                          color: Colors.white, size: 50),
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  )
                : _chewieController != null
                    ? Chewie(controller: _chewieController!)
                    : _imageBytes != null
                        ? PhotoView(
                            imageProvider: MemoryImage(_imageBytes!),
                            heroAttributes:
                                PhotoViewHeroAttributes(tag: widget.messageId),
                          )
                        : const SizedBox.shrink(),
      ),
    );
  }
}
