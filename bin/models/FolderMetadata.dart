import 'dart:convert';

class FolderMetadata {
  String name;
  int created;
  int modified;
  List<FolderMetadataFile> files;
  List<FolderMetadataFolder> folders;

  FolderMetadata(String name, int created, int modified) {
    this.name = name;
    this.created = created;
    this.modified = modified;
    this.folders = [];
    this.files = [];
  }

  static FolderMetadata toObject(List jsonObject) {
    final FolderMetadata folderMetadata =
        FolderMetadata(jsonObject[0], jsonObject[3], jsonObject[4]);

    for (var file in jsonObject[1]) {
      final FolderMetadataFile folderMetadataFile =
          FolderMetadataFile(file[0], file[1], file[2]);

      for (var version in file[3]) {
        final FolderMetadataFileVersion folderMetadataFileVersion =
            FolderMetadataFileVersion(
                version[0], version[1], version[2], version[3]);
        folderMetadataFile.versions.add(folderMetadataFileVersion);
      }
      folderMetadata.files.add(folderMetadataFile);
    }

    for (var folder in jsonObject[2]) {
      final FolderMetadataFolder folderMetadataFolder =
          FolderMetadataFolder(folder[0], folder[1]);
      folderMetadata.folders.add(folderMetadataFolder);
    }

    return folderMetadata;
  }

  @override
  String toString() {
    final asList = [];
    asList.add(this.name);

    final files = [];
    for (final FolderMetadataFile file in this.files) {
      final fileAsList = [];
      fileAsList.add(file.name);
      fileAsList.add(file.created);
      fileAsList.add(file.modified);

      final fileVersionList = [];
      for (FolderMetadataFileVersion version in file.versions) {
        final versionList = [];
        versionList.add(version.handle);
        versionList.add(version.size);
        versionList.add(version.created);
        versionList.add(version.modified);

        fileVersionList.add(versionList);
      }

      fileAsList.add(fileVersionList);

      files.add(fileAsList);
    }

    asList.add(files);

    final folders = [];
    for (final FolderMetadataFolder folder in this.folders) {
      final folderAsList = [];
      folderAsList.add(folder.name);
      folderAsList.add(folder.handle);
      folders.add(folderAsList);
    }

    asList.add(folders);

    asList.add(this.created);
    asList.add(this.modified);

    final String metadataAsString = JsonEncoder().convert(asList);
    return metadataAsString;
  }
}

class FolderMetadataFolder {
  String name;
  String handle;

  FolderMetadataFolder(String name, String handle) {
    this.name = name;
    this.handle = handle;
  }
}

class FolderMetadataFile {
  String name;
  int created;
  int modified;
  List<FolderMetadataFileVersion> versions;

  FolderMetadataFile(String name, int created, int modified) {
    this.name = name;
    this.created = created;
    this.modified = modified;
    this.versions = [];
  }
}

class FolderMetadataFileVersion {
  String handle;
  int size;
  int modified;
  int created;

  FolderMetadataFileVersion(
      String handle, int size, int modified, int created) {
    this.handle = handle;
    this.size = size;
    this.modified = modified;
    this.created = created;
  }
}
