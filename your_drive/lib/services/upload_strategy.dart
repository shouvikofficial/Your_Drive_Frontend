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

    // 🔹 Very small file → no chunking (direct upload)
    if (mb <= 3) {
      return UploadStrategy(
        chunkSize: fileSize,
        parallelChunks: 1,
        useChunking: false,
      );
    }

    // 🔹 Small to medium files
    if (mb <= 100) {
      return UploadStrategy(
        chunkSize: 2 * 1024 * 1024, // 2MB
        parallelChunks: 1, // 🔥 Proton-style sequential
        useChunking: true,
      );
    }

    // 🔹 Medium to large files
    if (mb <= 1024) {
      return UploadStrategy(
        chunkSize: isWifi
            ? 4 * 1024 * 1024 // 4MB on WiFi
            : 2 * 1024 * 1024, // 2MB on mobile
        parallelChunks: 1, // 🔥 Important fix
        useChunking: true,
      );
    }

    // 🔹 Very large files (1GB+)
    return UploadStrategy(
      chunkSize: isWifi
          ? 6 * 1024 * 1024 // safer than 8MB
          : 3 * 1024 * 1024,
      parallelChunks: 1, // 🔥 Always 1 for mobile stability
      useChunking: true,
    );
  }
}