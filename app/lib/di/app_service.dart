import 'package:package_info_plus/package_info_plus.dart';

class AppService {

  late PackageInfo packageInfo;
  bool autoUpdateScript = true;

  AppService() {
    PackageInfo.fromPlatform().then((val) {
      packageInfo = val;
    });
  }
}