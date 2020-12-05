import 'dart:typed_data';
import 'dart:convert';

import 'package:bip32/bip32.dart' as bip32;
import 'package:convert/convert.dart' as convert;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:pointycastle/digests/keccak.dart';

import './models/Constants.dart' show Constants;
import './models/FileMetadata.dart' show FileMetaoptions;

bip32.BIP32 getFolderHDKey(bip32.BIP32 key, String folder) {
  return generateSubHDKey(key, 'folder: ' + folder);
}

bip32.BIP32 generateSubHDKey(bip32.BIP32 key, String path) {
  final String hashedPath =
      convert.hex.encode(KeccakDigest(256).process(utf8.encode(path)));
  final String bipPath = hashToPath(hashedPath);

  final bip32.BIP32 derivedKey = key.derivePath(bipPath);
  return derivedKey;
}

String hashToPath(String hash) {
  String result = 'm/';
  for (var i = 0; i < hash.length; i += 4) {
    result += int.parse(hash.substring(i, i + 4), radix: 16).toString() + "'/";
  }
  return result.substring(0, result.length - 1);
}

String generateHashedFolderKey(bip32.BIP32 folderKey) {
  final String keccak256AsHex = convert.hex.encode(KeccakDigest(256)
      .process(utf8.encode(convert.hex.encode(folderKey.publicKey))));
  return keccak256AsHex;
}

String generateFolderKeyString(bip32.BIP32 folderKey) {
  final String keccak256AsHex = convert.hex.encode(KeccakDigest(256)
      .process(utf8.encode(convert.hex.encode(folderKey.privateKey))));
  return keccak256AsHex;
}

Future<String> decrypt(Uint8List encryptedData, String keyString) async {
  // [rawData + MAC]

  final Uint8List rawData =
      encryptedData.sublist(0, encryptedData.length - Constants.IV_BYTE_LENGTH);
  final Uint8List iv = encryptedData.sublist(rawData.length);

  final Uint8List key = Uint8List.fromList(convert.hex.decode(keyString));

  final Uint8List decrypted = await cryptography.AesGcm().decrypt(rawData,
      secretKey: cryptography.SecretKey(key), nonce: cryptography.Nonce(iv));

  final text = Utf8Decoder().convert(decrypted);
  return text;
}

Future encrypt(String rawData, Uint8List key) async {
  final cryptography.Nonce iv =
      cryptography.Nonce.randomBytes(Constants.IV_BYTE_LENGTH);

  final Uint8List encrypted = await cryptography.aesGcm.encrypt(
      utf8.encode(rawData),
      secretKey: cryptography.SecretKey(key),
      nonce: iv);

  final List<int> result = encrypted + iv.bytes;
  return result;
}

int getUploadSize(int fileSize) {
  final int blockSize = Constants.DEFAULT_BLOCK_SIZE;
  final int blockCount = (fileSize / blockSize).ceil();
  return fileSize + (blockCount * Constants.BLOCK_OVERHEAD);
}

int getEndIndex(int uploadSize, FileMetaoptions fileMetaoptions) {
  final int blockSize = fileMetaoptions.blockSize;
  final int partSize = fileMetaoptions.partSize;
  final int chunkSize = blockSize + Constants.BLOCK_OVERHEAD;
  final int chunkCount = (uploadSize / chunkSize).ceil();
  final int chunksPerPart = (partSize / chunkSize).ceil();
  // theoretically: endIndex = (uploadSize/partSize).ceil()
  final int endIndex = (chunkCount / chunksPerPart).ceil();
  return endIndex;
}
