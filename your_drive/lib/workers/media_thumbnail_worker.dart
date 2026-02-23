import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// 🔵 IMAGE Thumbnail Generator
Future<Uint8List?> generateImageThumbnail(String path) async {
  return await FlutterImageCompress.compressWithFile(
    path,
    minWidth: 300,
    quality: 70,
    format: CompressFormat.jpeg,
  );
}

/// 🔴 VIDEO Thumbnail Generator
Future<Uint8List?> generateVideoThumbnail(String path) async {
  return await VideoThumbnail.thumbnailData(
    video: path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 300,
    quality: 70,
  );
}