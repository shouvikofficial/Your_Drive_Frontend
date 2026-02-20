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
  // DOWNLOAD FULL FILE + SAFE CHUNK DECRYPT
  // =========================================================
  Future<void> _downloadAndDecrypt() async {
    try {
      final supabase = Supabase.instance.client;

      final fileData = await supabase
          .from('files')
          .select('iv, chunk_size, total_chunks')
          .eq('message_id', widget.messageId)
          .maybeSingle();

      if (fileData == null) throw Exception("Metadata missing");

      final ivBase64 = fileData['iv'];
      final int chunkSize = fileData['chunk_size'];
      final int totalChunks = fileData['total_chunks'];

      if (ivBase64 == null) {
        throw Exception("Missing IV");
      }

      final url = "${Env.backendBaseUrl}/api/file/${widget.messageId}";

      // 🔥 STEP 1: Download FULL encrypted file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception("Download failed");
      }

      final encryptedBytes = response.bodyBytes;

      // 🔥 STEP 2: Decrypt deterministically
      final decryptedFile = await _decryptFullFile(
        encryptedBytes,
        ivBase64,
        chunkSize,
        totalChunks,
      );

      if (!mounted) return;

      // 🔥 STEP 3: Display
      if (_isImage(widget.fileName)) {
        final bytes = await decryptedFile.readAsBytes();
        setState(() {
          _imageBytes = bytes;
          _isLoading = false;
        });
      } else if (_isVideo(widget.fileName)) {
        _tempFile = decryptedFile;
        await _initializeVideo();
      } else {
        _tempFile = decryptedFile;
        await OpenFilex.open(_tempFile!.path);
        if (mounted) Navigator.pop(context);
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
  // FULL FILE CHUNK DECRYPT (NO STREAM GUESSING)
  // =========================================================
  Future<File> _decryptFullFile(
    List<int> encryptedBytes,
    String ivBase64,
    int chunkSize,
    int totalChunks,
  ) async {
    final baseNonce = base64Decode(ivBase64);
    final secretKey = await VaultService().getSecretKey();
    final algorithm = AesGcm.with256bits();

    final output = BytesBuilder();
    int offset = 0;

    for (int i = 0; i < totalChunks; i++) {
      final int end = (i == totalChunks - 1)
          ? encryptedBytes.length
          : offset + chunkSize + 16;

      final chunk = encryptedBytes.sublist(offset, end);

      final macBytes = chunk.sublist(chunk.length - 16);
      final cipherText = chunk.sublist(0, chunk.length - 16);

      final nonce = Uint8List.fromList(baseNonce);
      nonce[8] = (i >> 24) & 0xFF;
      nonce[9] = (i >> 16) & 0xFF;
      nonce[10] = (i >> 8) & 0xFF;
      nonce[11] = i & 0xFF;

      final decrypted = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: secretKey,
      );

      output.add(decrypted);
      offset = end;
    }

    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/${widget.fileName}");
    await file.writeAsBytes(output.toBytes());

    return file;
  }

  // =========================================================
  // VIDEO PLAYER
  // =========================================================
  Future<void> _initializeVideo() async {
    try {
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
  // FILE TYPE CHECK
  // =========================================================
  bool _isImage(String name) =>
      RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp|heic)$',
              caseSensitive: false)
          .hasMatch(name);

  bool _isVideo(String name) =>
      RegExp(r'\.(mp4|mov|avi|mkv|webm)$',
              caseSensitive: false)
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
        title: Text(widget.fileName,
            style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : _error != null
                ? Text(_error!,
                    style: const TextStyle(color: Colors.white))
                : _chewieController != null
                    ? Chewie(controller: _chewieController!)
                    : _imageBytes != null
                        ? PhotoView(
                            imageProvider: MemoryImage(_imageBytes!),
                          )
                        : const SizedBox.shrink(),
      ),
    );
  }
}