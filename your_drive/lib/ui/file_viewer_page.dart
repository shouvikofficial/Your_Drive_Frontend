import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart'; // For Image Zoom
import 'package:video_player/video_player.dart'; // For Video Logic
import 'package:chewie/chewie.dart'; // For Video UI
import '../config/env.dart';

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
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    final url = "${Env.backendBaseUrl}/api/file/${widget.messageId}";
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url));

    await _videoController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _videoController!.value.aspectRatio,
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text("Video Error: $errorMessage", style: const TextStyle(color: Colors.white)),
        );
      },
    );
    setState(() {});
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = "${Env.backendBaseUrl}/api/file/${widget.messageId}";

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(widget.fileName, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Center(
        child: widget.type == 'video'
            ? _buildVideoPlayer()
            : _buildImageViewer(url),
      ),
    );
  }

  Widget _buildImageViewer(String url) {
    return PhotoView(
      imageProvider: NetworkImage(url),
      heroAttributes: PhotoViewHeroAttributes(tag: widget.messageId), // 🚀 Smooth Animation
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorBuilder: (context, error, stackTrace) => const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, color: Colors.white, size: 50),
          SizedBox(height: 10),
          Text("Could not load image", style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    } else {
      return const CircularProgressIndicator(color: Colors.white);
    }
  }
}