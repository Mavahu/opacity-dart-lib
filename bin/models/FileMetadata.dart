import 'Constants.dart' show Constants;

class FileMetadata {
  String name;
  String type;
  int size;
  FileMetaoptions p;

  static FileMetadata toObject(Map data) {
    final fileMetadata = FileMetadata();

    fileMetadata.name = data['name'];
    fileMetadata.size = data['size'];
    fileMetadata.type = data['type'];
    fileMetadata.p = FileMetaoptions();

    return fileMetadata;
  }

  Map toJson() {
    final jsonObject = {
      'name': this.name,
      'type': this.type,
      'size': this.size,
      'p': {'blockSize': this.p.blockSize, 'partSize': this.p.partSize}
    };
    return jsonObject;
  }
}

class FileMetaoptions {
  int blockSize;
  int partSize;

  FileMetaoptions() {
    this.blockSize = Constants.DEFAULT_BLOCK_SIZE; // DEFAULT_BLOCK_SIZE
    this.partSize = Constants.DEFAULT_PART_SIZE;
  }
}
