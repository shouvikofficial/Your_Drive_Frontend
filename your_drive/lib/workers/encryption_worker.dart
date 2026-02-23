import 'package:cryptography/cryptography.dart';
import 'dart:typed_data';

class EncryptParams {
  final List<int> bytes;
  final List<int> keyBytes;
  final List<int> nonce;

  EncryptParams({
    required this.bytes,
    required this.keyBytes,
    required this.nonce,
  });
}

Future<List<int>> encryptChunkInIsolate(EncryptParams params) async {
  final algorithm = AesGcm.with256bits();

  final secretKey = SecretKey(params.keyBytes);

  final secretBox = await algorithm.encrypt(
    params.bytes,
    secretKey: secretKey,
    nonce: params.nonce,
  );

  return secretBox.cipherText + secretBox.mac.bytes;
}