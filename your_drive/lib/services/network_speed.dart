import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkSpeed {
  static Future<bool> isWifi() async {
    final result = await Connectivity().checkConnectivity();
    return result.contains(ConnectivityResult.wifi);
  }
}
