import 'dart:typed_data';
import 'dart:convert';

import 'package:bip32/bip32.dart' as bip32;
import 'package:convert/convert.dart' as convert;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:pointycastle/digests/keccak.dart';

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

Future<String> decrypt(Uint8List encryptedData, String keyString) async {
  // [rawData + MAC]
  final Uint8List rawData = encryptedData.sublist(0, encryptedData.length - 16);
  final Uint8List iv = encryptedData.sublist(rawData.length);

  final Uint8List key = Uint8List.fromList(convert.hex.decode(keyString));

  final decrypted = await cryptography.AesGcm().decrypt(rawData,
      secretKey: cryptography.SecretKey(key), nonce: cryptography.Nonce(iv));
  /*
  //throw ('Not functioanl');
  final params =
      AEADParameters(KeyParameter(key), 16 * 8, iv, Uint8List.fromList([]));
  final GCMBlockCipher decrypter = GCMBlockCipher(AESFastEngine())
    ..init(false, params);
  final Uint8List decrypted = decrypter.process(rawData);
  */

  final text = Utf8Decoder().convert(decrypted);
  return text;
}
