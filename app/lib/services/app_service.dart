import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/storage/app_storage.dart';

/// 应用全局系统与元信息服务
/// 
/// 负责管理系统主题模式（跟随系统/深色/浅色）、规则自动检查更新配置以及应用包元信息
class AppService {
  PackageInfo? packageInfo;
  bool autoUpdateScript = true;

  /// 持久化存储 Key
  static const String _themeModeKey = 'app_theme_mode';

  /// 响应式主题模式通知器
  final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// 当前生效的主题模式
  ThemeMode get themeMode => themeModeNotifier.value;

  AppService() {
    _initPackageInfo();
    _initThemeMode();
  }

  /// 初始化应用包信息
  Future<void> _initPackageInfo() async {
    try {
      packageInfo = await PackageInfo.fromPlatform();
    } catch (_) {}
  }

  /// 初始化持久化存储的主题模式配置
  Future<void> _initThemeMode() async {
    try {
      final savedMode = await AppStorage.getString(_themeModeKey);
      if (savedMode == 'light') {
        themeModeNotifier.value = ThemeMode.light;
      } else if (savedMode == 'dark') {
        themeModeNotifier.value = ThemeMode.dark;
      } else {
        themeModeNotifier.value = ThemeMode.system;
      }
    } catch (e) {
      debugPrint('【AppService】读取主题模式失败: $e');
    }
  }

  /// 更新并持久化全局主题模式
  Future<void> updateThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    String modeString = 'system';
    if (mode == ThemeMode.light) {
      modeString = 'light';
    } else if (mode == ThemeMode.dark) {
      modeString = 'dark';
    }
    await AppStorage.setString(_themeModeKey, modeString);
  }
}
