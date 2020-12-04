class Constants {
  static int FILENAME_MAX_LENGTH = 256;
  static int CURRENT_VERSION = 1;
  static int IV_BYTE_LENGTH = 16;
  static int TAG_BYTE_LENGTH = 16;
  static int TAG_BIT_LENGTH = TAG_BYTE_LENGTH * 8;
  static int DEFAULT_BLOCK_SIZE = 64 * 1024;
  static int BLOCK_OVERHEAD = TAG_BYTE_LENGTH + IV_BYTE_LENGTH;
  static int DEFAULT_PART_SIZE = 10485760;
  // no clue how to calc that number but normally it should be:
  // 128 * (DEFAULT_BLOCK_SIZE + BLOCK_OVERHEAD);
}
