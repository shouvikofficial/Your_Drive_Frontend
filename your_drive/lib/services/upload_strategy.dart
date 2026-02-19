class UploadStrategy {
  final int chunkSize;
  final int parallelChunks;
  final bool useChunking;

  UploadStrategy({
    required this.chunkSize,
    required this.parallelChunks,
    required this.useChunking,
  });

  static UploadStrategy decide({
    required int fileSize,
    required bool isWifi,
  }) {
    final mb = fileSize / (1024 * 1024);

    if (mb < 5) {
      return UploadStrategy(
        chunkSize: fileSize,
        parallelChunks: 1,
        useChunking: false,
      );
    }

    if (mb < 100) {
      return UploadStrategy(
        chunkSize: 2 * 1024 * 1024,
        parallelChunks: isWifi ? 3 : 2,
        useChunking: true,
      );
    }

    if (mb < 1024) {
      return UploadStrategy(
        chunkSize: isWifi ? 4 * 1024 * 1024 : 2 * 1024 * 1024,
        parallelChunks: isWifi ? 4 : 3,
        useChunking: true,
      );
    }

    return UploadStrategy(
      chunkSize: isWifi ? 8 * 1024 * 1024 : 4 * 1024 * 1024,
      parallelChunks: isWifi ? 6 : 3,
      useChunking: true,
    );
  }
}
