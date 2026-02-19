class RetryHelper {
  static Future<T> retry<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
  }) async {
    int attempt = 0;

    while (true) {
      try {
        return await fn();
      } catch (_) {
        attempt++;
        if (attempt >= maxAttempts) rethrow;
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }
}
