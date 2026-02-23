import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart'; // Required for RootIsolateToken
import 'package:convert/convert.dart';   // Required for AccumulatorSink
import '../services/saf_service.dart';   // Import your existing SafService

// ================= Standard File Worker =================
Future<String> hashFileInIsolate(String path) async {
  final file = File(path);
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

// ================= SAF Worker Parameters =================
class SafHashParams {
  final RootIsolateToken token; // Key to unlocking Platform Channels in Isolate
  final String uri;
  final int fileSize;

  SafHashParams({
    required this.token,
    required this.uri,
    required this.fileSize,
  });
}

// ================= SAF Isolate Worker =================
Future<String> hashSafInIsolate(SafHashParams params) async {
  // 1. Initialize the background isolate to allow MethodChannels (SAF)
  BackgroundIsolateBinaryMessenger.ensureInitialized(params.token);

  const int hashChunk = 1024 * 1024; // 1MB chunks
  int offset = 0;

  final sink = AccumulatorSink<Digest>();
  final input = sha256.startChunkedConversion(sink);

  try {
    while (offset < params.fileSize) {
      // Calculate read length
      final readLen = (offset + hashChunk > params.fileSize)
          ? params.fileSize - offset
          : hashChunk;

      // 2. Read from SAF (This runs on background thread now!)
      final bytes = await SafService.readChunk(
        uri: params.uri,
        offset: offset,
        length: readLen,
      );

      if (bytes == null) throw Exception("SAF read failed inside isolate");

      // 3. Update Hash
      input.add(bytes);
      offset += readLen;
    }
  } finally {
    input.close();
  }

  return sink.events.single.toString();
}