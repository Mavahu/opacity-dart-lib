import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;

import 'package:bip32/bip32.dart' as bip32;
import 'package:convert/convert.dart' as convert;
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/src/utils.dart' show encodeBigInt, decodeBigInt;
import 'package:path/path.dart' as pth;
import 'package:cryptography/cryptography.dart' as cryptography;

import 'Utils.dart' as Utils;
import './models/FolderMetadata.dart' show FolderMetadata, FolderMetadataFile;
import './models/FileMetadata.dart' show FileMetadata;

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
    final String payloadHash =
        convert.hex.encode(KeccakDigest(256).process(utf8.encode(payload)));

    // https://pub.dev/documentation/ethereum_util/latest/ethereum_util/sign.html
    final ECDSASigner signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
    final NormalizedECDSASigner signer2 =
        NormalizedECDSASigner(signer, enforceNormalized: true);
    final ECPrivateKey key = ECPrivateKey(
        decodeBigInt(masterKey.privateKey), ECDomainParameters('secp256k1'));
    signer2.init(true, PrivateKeyParameter(key));
    final ECSignature signatureObject =
        signer2.generateSignature(convert.hex.decode(payloadHash));

    // r + s => signature
    final String signature =
        convert.hex.encode(encodeBigInt(signatureObject.r, 32)) +
            convert.hex.encode(encodeBigInt(signatureObject.s, 32));
    if (signature.length != 128) {
      throw ('Signature has an invalid length');
    }

    return {
      'requestBody': payload,
      'signature': signature,
      'publicKey': convert.hex.encode(masterKey.publicKey),
      'hash': payloadHash
    };
  }

  Map<String, String> signPayloadForm(String rawPayload) {
    final String payloadHash =
        convert.hex.encode(KeccakDigest(256).process(utf8.encode(rawPayload)));

    // https://pub.dev/documentation/ethereum_util/latest/ethereum_util/sign.html
    final ECDSASigner signer = ECDSASigner(null, HMac(SHA256Digest(), 64));
    final NormalizedECDSASigner signer2 =
        NormalizedECDSASigner(signer, enforceNormalized: true);
    final ECPrivateKey key = ECPrivateKey(
        decodeBigInt(masterKey.privateKey), ECDomainParameters('secp256k1'));
    signer2.init(true, PrivateKeyParameter(key));
    final ECSignature signatureObject =
        signer2.generateSignature(convert.hex.decode(payloadHash));

    // r + s => signature
    final String signature =
        convert.hex.encode(encodeBigInt(signatureObject.r, 32)) +
            convert.hex.encode(encodeBigInt(signatureObject.s, 32));
    if (signature.length != 128) {
      throw ('Signature has an invalid length');
    }

    return {
      'requestBody': rawPayload,
      'signature': signature,
      'publicKey': convert.hex.encode(masterKey.publicKey),
      'hash': payloadHash
    };
  }

  Future<FolderMetadata> getFolderMetadata(String folder) async {
    final Map returnValues = createMetadataKeyAndString(folder);
    final String hashedFolderKey = returnValues['hashedFolderKey'];
    final String keyString = returnValues['keyString'];

    return await getFolderMetadataRequest(hashedFolderKey, keyString);
  }

  Map<String, String> createMetadataKeyAndString(String folder) {
    final bip32.BIP32 folderKey = Utils.getFolderHDKey(masterKey, folder);
    final String hashedFolderKey = Utils.generateHashedFolderKey(folderKey);
    final String keyString = Utils.generateFolderKeyString(folderKey);

    return {'hashedFolderKey': hashedFolderKey, 'keyString': keyString};
  }

  Future<FolderMetadata> getFolderMetadataRequest(
      String hashedFolderKey, String keyString) async {
    final Map rawPayload = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'metadataKey': hashedFolderKey
    };

    final String rawPayloadJson = JsonEncoder().convert(rawPayload);
    final Map payload = signPayload(rawPayloadJson);
    final String payloadJson = JsonEncoder().convert(payload);

    final response = await http.post(baseUrl + 'metadata/get',
        body: payloadJson, headers: {'Content-Type': 'application/json'});

    final encryptedMetadataString =
        JsonDecoder().convert(response.body)['metadata'];
    final Uint8List encryptedMetadataBytes =
        base64.decode(encryptedMetadataString);

    final decrypted = await Utils.decrypt(encryptedMetadataBytes, keyString);
    final metadataAsList = JsonDecoder().convert(decrypted);

    final metadata = FolderMetadata.toObject(metadataAsList);

    return metadata;
  }

  void uploadFile(String folder, String filePath) async {
    final String fileName = pth.basename(filePath);
    final io.File file = io.File(filePath);
    final int fileSize = await file.length();
    final Map fileData = {
      'path': filePath,
      'name': fileName,
      'size': fileSize,
      'type': ''
    };

    final FolderMetadata metadataToCheckIn =
        await this.getFolderMetadata(folder);
    for (final FolderMetadataFile file in metadataToCheckIn.files) {
      if (file.name == fileName) {
        print('File: $fileName exists already');
        return;
      }
    }

    final FileMetadata fileMetadata = FileMetadata.toObject(fileData);
    final int uploadSize = Utils.getUploadSize(fileMetadata.size);
    final int endIndex = Utils.getEndIndex(uploadSize, fileMetadata.p);

    final Uint8List handle = cryptography.Nonce.randomBytes(64).bytes;
    final Uint8List keyBytes = handle.sublist(32);

    final String fileMetadataAsString =
        JsonEncoder().convert(fileMetadata.toJson());
    final encryptedFileMetadataBytes =
        await Utils.encrypt(fileMetadataAsString, keyBytes);

    final String handleHex = convert.hex.encode(handle);
    final String fileId = handleHex.substring(0, 64);

    final Map<String, dynamic> requestBody = {
      'fileHandle': fileId,
      'fileSizeInByte': uploadSize,
      'endIndex': endIndex
    };

    final String requestBodyAsString = jsonEncode(requestBody);
    final Map<String, String> form = this.signPayloadForm(requestBodyAsString);

    var request =
        http.MultipartRequest('POST', Uri.parse(this.baseUrl + 'init-upload'))
          ..fields.addAll(form);
    var response = await request.send();
    if (response.statusCode != 200) {
      throw ('Failed to initiate file upload');
    }

    print("");
  }
}

void main() async {
  final OpacityAccount account = OpacityAccount(
      'c18dee8900ef65150cc0f5cc931c4a241dc6e02dc60f0edac22fc16ff629d9676091fd781d82eccc747fc32e835c581d14990f2f9c3f271ec35fb5b35c6124ba');

  await account.uploadFile(
      '/', r'C:\Users\Martin\Pictures\bisaflor normal\IMG_20201101_131706.jpg');
}
