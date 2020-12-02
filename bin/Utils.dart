import 'dart:typed_data';
import 'dart:convert';

import 'package:bip32/bip32.dart' as bip32;
import 'package:convert/convert.dart' as convert;
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/export.dart';

bip32.BIP32 getFolderHDKey(bip32.BIP32 key, String folder) {
  return generateSubHDKey(key, 'folder: ' + folder);
}

bip32.BIP32 generateSubHDKey(bip32.BIP32 key, String path) {
  // old way using ethereum_util lib
  // - final String hashedPath = convert.hex.encode(eth.keccak256(path));
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
  /*
  - old way using ethereum_utils library:
  final data = convert.hex
      .encode(eth.keccak256(convert.hex.encode(folderKey.publicKey)));
   */
}

String generateFolderKeyString(bip32.BIP32 folderKey) {
  final String keccak256AsHex = convert.hex.encode(KeccakDigest(256)
      .process(utf8.encode(convert.hex.encode(folderKey.privateKey))));
  return keccak256AsHex;

  // old way using ethereum_utils library
  // final data = convert.hex.encode(eth.keccak256(convert.hex.encode(folderKey.privateKey)));
}

void decrypt(Uint8List encryptedData, String keyString) async {
  final Uint8List rawData = encryptedData.sublist(0, encryptedData.length - 32);
  final Uint8List authTag =
      encryptedData.sublist(rawData.length, rawData.length + 16);
  final Uint8List iv = encryptedData.sublist(authTag.length + rawData.length);

  final Uint8List key = Uint8List.fromList(convert.hex.decode(keyString));

  final params = AEADParameters(KeyParameter(key), 16 * 8, iv, Uint8List(0));
  throw ('Not functioanl');
  final decrypter = GCMBlockCipher(AESFastEngine())..init(false, params);
  final decrypted = decrypter.process(rawData);

  print(decrypted);
}
