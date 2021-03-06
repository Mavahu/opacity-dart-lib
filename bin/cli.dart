import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:bip32/bip32.dart' as bip32;
import 'package:convert/convert.dart' as convert;
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/src/utils.dart' show encodeBigInt, decodeBigInt;
import 'package:path/path.dart' as pth;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:semaphore/semaphore.dart' as semaphore;

import 'Utils.dart' as Utils;
import './models/FolderMetadata.dart'
    show FolderMetadata, FolderMetadataFile, FolderMetadataFileVersion;
import './models/FileMetadata.dart' show FileMetadata;

class OpacityAccount {
  String baseUrl = 'https://broker-1.opacitynodes.com:3000/api/v1/';
  String handle;
  String privateKey;
  String chainCode;
  bip32.BIP32 masterKey;
  int maxSimultaneousPartsUpload;

  OpacityAccount(String handle) {
    this.handle = handle;
    privateKey = this.handle.substring(0, 64);
    chainCode = this.handle.substring(64);
    masterKey = bip32.BIP32.fromPrivateKey(
        Uint8List.fromList(convert.hex.decode(privateKey)),
        Uint8List.fromList(convert.hex.decode(chainCode)));
    this.maxSimultaneousPartsUpload = 5;
  }

  Map<String, String> signPayload(String payload) {
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
    final fileStats = file.statSync();
    final int fileSize = fileStats.size;
    final Map<String, dynamic> fileData = {
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

    print('$fileName: Starting upload');

    final FileMetadata fileMetadata = FileMetadata.toObject(fileData);
    final int uploadSize = Utils.getUploadSize(fileMetadata.size);
    final int endIndex = Utils.getEndIndex(uploadSize, fileMetadata.p);

    final Uint8List handle = cryptography.Nonce.randomBytes(64).bytes;
    final String handleHex = convert.hex.encode(handle);
    final String fileId = handleHex.substring(0, 64);

    final Map<String, dynamic> requestBody = {
      'fileHandle': fileId,
      'fileSizeInByte': uploadSize,
      'endIndex': endIndex
    };

    final String requestBodyAsString = jsonEncode(requestBody);
    final Map<String, String> requestFields =
        this.signPayload(requestBodyAsString);

    final Uint8List keyBytes = handle.sublist(32);
    final String fileMetadataAsString =
        JsonEncoder().convert(fileMetadata.toJson());
    final encryptedFileMetadataBytes =
        await Utils.encrypt(utf8.encode(fileMetadataAsString), keyBytes);

    final request =
        http.MultipartRequest('POST', Uri.parse(this.baseUrl + 'init-upload'))
          ..fields.addAll(requestFields)
          ..files.add(http.MultipartFile.fromBytes(
              'metadata', encryptedFileMetadataBytes,
              filename: 'metadata'));
    var response = await request.send();
    if (response.statusCode != 200) {
      throw ('Failed to initiate file upload');
    }

    print('$fileName: Initiated upload');

    // Upload all parts of the file

    final sm = semaphore.LocalSemaphore(this.maxSimultaneousPartsUpload);
    final List<Future> futures = <Future>[];
    for (int partIndex = 0; partIndex < endIndex; partIndex++) {
      futures.add(this.uploadFilePart(
          partIndex, endIndex, fileData, fileMetadata, keyBytes, fileId, sm));
    }
    await Future.wait(futures);
    print('$fileName: Uploaded all parts');

    //verify upload & retry -> implement later
    /*
    final verifyBody = {'fileHandle': fileId};
    final verifyBodyString = json.encode(verifyBody);
    final payload = this.signPayload(verifyBodyString);
    final payloadString = json.encode(payload);

    final resp =
        await http.post(baseUrl + 'upload-status', body: payloadString);
    */

    //Append Metadata

    final FolderMetadataFile folderMetadataFile = FolderMetadataFile(
        fileMetadata.name,
        fileStats.modified.millisecondsSinceEpoch,
        fileStats.modified.millisecondsSinceEpoch);
    folderMetadataFile.versions.add(FolderMetadataFileVersion(
        handleHex,
        fileMetadata.size,
        fileStats.modified.millisecondsSinceEpoch,
        fileStats.modified.millisecondsSinceEpoch));

    final FolderMetadata metadata = await this.getFolderMetadata(folder);
    metadata.files.add(folderMetadataFile);
    await this.setMetadata(metadata);
    print('$fileName: Finished upload');
  }

  Future uploadFilePart(
      int partIndex,
      int endIndex,
      Map fileData,
      FileMetadata fileMetadata,
      Uint8List keyBytes,
      String fileId,
      semaphore.LocalSemaphore localSemaphore) async {
    try {
      await localSemaphore.acquire();
      print('${fileData['name']}: Uploading part ${partIndex + 1} / $endIndex');

      final Uint8List rawPart =
          await Utils.getPartial(fileData, fileMetadata.p.partSize, partIndex);
      final int chunksTotalAmount =
          (rawPart.length / fileMetadata.p.blockSize).ceil();
      List<int> encryptedChunks = [];
      // move the chunk encryption in its own function
      for (int chunkIndex = 0; chunkIndex < chunksTotalAmount; chunkIndex++) {
        final int remaining =
            rawPart.length - chunkIndex * fileMetadata.p.blockSize;
        if (remaining <= 0) {
          break;
        }
        final int chunkSize = math.min(fileMetadata.p.blockSize, remaining);
        final Uint8List chunk = rawPart.sublist(
            chunkIndex * fileMetadata.p.blockSize,
            chunkIndex * fileMetadata.p.blockSize + chunkSize);
        final Uint8List encryptedChunk = await Utils.encrypt(chunk, keyBytes);
        encryptedChunks.addAll(encryptedChunk);
      }

      final Map<String, dynamic> requestBody = {
        'fileHandle': fileId,
        'partIndex': partIndex + 1,
        'endIndex': endIndex
      };
      final String requestBodyString = json.encode(requestBody);
      final Map<String, String> requestForm =
          this.signPayload(requestBodyString);
      final request =
          http.MultipartRequest('POST', Uri.parse(this.baseUrl + 'upload'))
            ..fields.addAll(requestForm)
            ..files.add(http.MultipartFile.fromBytes(
                'chunkData', encryptedChunks,
                filename: 'chunkData'));
      var response = await request.send();
      if (response.statusCode != 200) {
        throw ('Failed to upload part ${partIndex + 1}/$endIndex of ${fileMetadata.name}');
      }
    } finally {
      localSemaphore.release();
    }
  }

  Future setMetadata(FolderMetadata metadata) async {
    final Map returnValues = createMetadataKeyAndString(
        metadata.name == 'Folder' ? '/' : metadata.name);
    final String hashedFolderKey = returnValues['hashedFolderKey'];
    final String keyString = returnValues['keyString'];

    final String folderMetadataString = metadata.toString();

    final Uint8List encryptedFolderMetadata = await Utils.encrypt(
        utf8.encode(folderMetadataString), convert.hex.decode(keyString));

    final String encryptedFolderMetadataBase64 =
        base64.encode(encryptedFolderMetadata);

    final rawPayload = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'metadataKey': hashedFolderKey,
      'metadata': encryptedFolderMetadataBase64
    };

    final rawPayloadString = json.encode(rawPayload);
    final payload = this.signPayload(rawPayloadString);
    final payloadString = json.encode(payload);

    final response = await http.post(baseUrl + 'metadata/set',
        body: payloadString, headers: {'Content-Type': 'application/json'});
    if (response.statusCode != 200) {
      throw ('Failed to set metadata of ${metadata.name}');
    }
  }
}

void main() async {
  final OpacityAccount account = OpacityAccount(
      'c18dee8900ef65150cc0f5cc931c4a241dc6e02dc60f0edac22fc16ff629d9676091fd781d82eccc747fc32e835c581d14990f2f9c3f271ec35fb5b35c6124ba');

  final ret = await account.uploadFile(
      '/', r"C:\Users\Martin\Downloads\ed026f6cf236865d65ce8d69b4eeba82.mp4");
  return;
}
