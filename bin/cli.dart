import 'dart:convert';
import 'dart:typed_data';

//import 'package:ethereum_util/ethereum_util.dart' as eth;
import 'package:bip32/bip32.dart' as bip32;
import 'package:convert/convert.dart' as convert;
import 'package:http/http.dart' as http;
import 'package:cryptography/cryptography.dart' as cryptography;

import 'Utils.dart' as Utils;

class OpacityAccount {
  String baseUrl = 'https://broker-1.opacitynodes.com:3000/api/v1/';
  String handle;
  String privateKey;
  String chainCode;
  bip32.BIP32 masterKey;

  OpacityAccount(String handle) {
    this.handle = handle;
    privateKey = this.handle.substring(0, 64);
    chainCode = this.handle.substring(64);
    masterKey = bip32.BIP32.fromPrivateKey(
        Uint8List.fromList(convert.hex.decode(privateKey)),
        Uint8List.fromList(convert.hex.decode(chainCode)));
  }

  Map signPayload(String payload) {
    /*final String payloadHash = convert.hex.encode(eth.keccak256(payload));
    final eth.ECDSASignature signatureObject = eth.sign(
        Uint8List.fromList(convert.hex.decode(payloadHash)),
        masterKey.privateKey);
    // r + s => signature
    final String signature = signatureObject.r.toRadixString(16) +
        signatureObject.s.toRadixString(16);
    return {
      'requestBody': payload,
      'signature': signature,
      'publicKey': convert.hex.encode(masterKey.publicKey),
      'hash': payloadHash
    };*/
    return {};
  }

  dynamic getFolderMetadata(String folder) async {
    final Map returnValues = createMetadataKeyAndString(folder);
    final String hashedFolderKey = returnValues['hashedFolderKey'];
    final String keyString = returnValues['keyString'];

    await getFolderMetadataRequest(hashedFolderKey, keyString);
  }

  Map<String, String> createMetadataKeyAndString(String folder) {
    final bip32.BIP32 folderKey = Utils.getFolderHDKey(masterKey, folder);
    final String hashedFolderKey = Utils.generateHashedFolderKey(folderKey);
    final String keyString = Utils.generateFolderKeyString(folderKey);

    return {'hashedFolderKey': hashedFolderKey, 'keyString': keyString};
  }

  dynamic getFolderMetadataRequest(
      String hashedFolderKey, String keyString) async {
    final Map rawPayload = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'metadataKey': hashedFolderKey
    };
    final String rawPayloadJson = JsonEncoder().convert(rawPayload);
    final Map payload = signPayload(rawPayloadJson);
    final String payloadJson = JsonEncoder().convert(payload);

    var response = await http.post(baseUrl + 'metadata/get', body: payloadJson);

    var encryptedMetadataString =
        JsonDecoder().convert(response.body)['metadata'];
    final Uint8List encryptedMetadataBytes =
        base64.decode(encryptedMetadataString);

    var decrypted = await Utils.decrypt(encryptedMetadataBytes, keyString);
  }
}

void main() async {
  final OpacityAccount account = OpacityAccount(
      'c18dee8900ef65150cc0f5cc931c4a241dc6e02dc60f0edac22fc16ff629d9676091fd781d82eccc747fc32e835c581d14990f2f9c3f271ec35fb5b35c6124ba');

  await account.getFolderMetadata('/');
}
