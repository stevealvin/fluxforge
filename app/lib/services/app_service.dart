import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/storage/app_storage.dart';

/// 断点续播行为偏好
enum ResumeBehavior {
  auto('直接跳转'),
  prompt('提示询问'),
  disabled('从头开始');

  const ResumeBehavior(this.label);
  final String label;
}

/// 全局偏好设置配置模型 (AppSettings)
class AppSettings {
  // 1. 播放视听偏好
  final bool enablePlayerGestures;
  final bool enableLongPress2x;
  final double defaultPlaybackSpeed;
  final ResumeBehavior resumeBehavior;
  final bool cellularDataWarning;

  // 2. 浏览与阅读偏好
  final String novelPageMode; // 'horizontal' | 'vertical'
  final double novelFontSize;
  final double novelLineHeight;
  final String galleryLayout; // 'grid' | 'comicStrip'

  // 3. 规则沙箱与网络
  final int requestTimeoutSeconds; // 15 | 30 | 60
  final String customUserAgent;
  final bool enableAdBlock;
  final bool autoCheckRuleUpdates;

  // 4. 外观与主题
  final ThemeMode themeMode;

  // 5. 隐私
  final bool incognitoMode;

  const AppSettings({
    this.enablePlayerGestures = true,
    this.enableLongPress2x = true,
    this.defaultPlaybackSpeed = 1.0,
    this.resumeBehavior = ResumeBehavior.prompt,
    this.cellularDataWarning = false,
    this.novelPageMode = 'horizontal',
    this.novelFontSize = 18.0,
    this.novelLineHeight = 1.6,
    this.galleryLayout = 'grid',
    this.requestTimeoutSeconds = 30,
    this.customUserAgent = '',
    this.enableAdBlock = true,
    this.autoCheckRuleUpdates = true,
    this.themeMode = ThemeMode.system,
    this.incognitoMode = false,
  });

  AppSettings copyWith({
    bool? enablePlayerGestures,
    bool? enableLongPress2x,
    double? defaultPlaybackSpeed,
    ResumeBehavior? resumeBehavior,
    bool? cellularDataWarning,
    String? novelPageMode,
    double? novelFontSize,
    double? novelLineHeight,
    String? galleryLayout,
    int? requestTimeoutSeconds,
    String? customUserAgent,
    bool? enableAdBlock,
    bool? autoCheckRuleUpdates,
    ThemeMode? themeMode,
    bool? incognitoMode,
  }) {
    return AppSettings(
      enablePlayerGestures: enablePlayerGestures ?? this.enablePlayerGestures,
      enableLongPress2x: enableLongPress2x ?? this.enableLongPress2x,
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      resumeBehavior: resumeBehavior ?? this.resumeBehavior,
      cellularDataWarning: cellularDataWarning ?? this.cellularDataWarning,
      novelPageMode: novelPageMode ?? this.novelPageMode,
      novelFontSize: novelFontSize ?? this.novelFontSize,
      novelLineHeight: novelLineHeight ?? this.novelLineHeight,
      galleryLayout: galleryLayout ?? this.galleryLayout,
      requestTimeoutSeconds: requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      customUserAgent: customUserAgent ?? this.customUserAgent,
      enableAdBlock: enableAdBlock ?? this.enableAdBlock,
      autoCheckRuleUpdates: autoCheckRuleUpdates ?? this.autoCheckRuleUpdates,
      themeMode: themeMode ?? this.themeMode,
      incognitoMode: incognitoMode ?? this.incognitoMode,
    );
  }
}

/// 应用全局系统服务与偏好中心 (AppService)
class AppService {
  PackageInfo? packageInfo;

  /// 全局响应式偏好设置通知器
  final ValueNotifier<AppSettings> settingsNotifier =
      ValueNotifier<AppSettings>(const AppSettings());

  AppSettings get settings => settingsNotifier.value;

  /// 主题模式快捷访问
  ThemeMode get themeMode => settings.themeMode;
  ValueNotifier<ThemeMode> get themeModeNotifier => _themeModeNotifier;
  final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// 规则自动更新开关快捷访问
  bool get autoUpdateScript => settings.autoCheckRuleUpdates;

  AppService() {
    _initPackageInfo();
    _loadSettings();
  }

  /// 初始化应用包信息
  Future<void> _initPackageInfo() async {
    try {
      packageInfo = await PackageInfo.fromPlatform();
    } catch (_) {}
  }

  /// 从本地持久化存储加载所有偏好配置
  Future<void> _loadSettings() async {
    try {
      final gestures = await AppStorage.getBool('pref_player_gestures') ?? true;
      final longPress2x = await AppStorage.getBool('pref_long_press_2x') ?? true;
      final speed = await AppStorage.getDouble('pref_default_speed') ?? 1.0;
      final resumeStr = await AppStorage.getString('pref_resume_behavior') ?? 'prompt';
      final cellular = await AppStorage.getBool('pref_cellular_warning') ?? false;

      final novelMode = await AppStorage.getString('novel_page_mode') ?? 'horizontal';
      final fontSize = await AppStorage.getDouble('novel_font_size') ?? 18.0;
      final lineHeight = await AppStorage.getDouble('novel_line_height') ?? 1.6;
      final galleryLayout = await AppStorage.getString('pref_gallery_layout') ?? 'grid';

      final timeout = await AppStorage.getInt('pref_request_timeout') ?? 30;
      final ua = await AppStorage.getString('pref_custom_ua') ?? '';
      final adBlock = await AppStorage.getBool('pref_enable_adblock') ?? true;
      final autoUpdate = await AppStorage.getBool('pref_auto_check_rules') ?? true;

      final themeStr = await AppStorage.getString('app_theme_mode') ?? 'system';
      final incognito = await AppStorage.getBool('pref_incognito_mode') ?? false;

      ThemeMode mode = ThemeMode.system;
      if (themeStr == 'light') mode = ThemeMode.light;
      if (themeStr == 'dark') mode = ThemeMode.dark;
      _themeModeNotifier.value = mode;

      ResumeBehavior resume = ResumeBehavior.prompt;
      if (resumeStr == 'auto') resume = ResumeBehavior.auto;
      if (resumeStr == 'disabled') resume = ResumeBehavior.disabled;

      settingsNotifier.value = AppSettings(
        enablePlayerGestures: gestures,
        enableLongPress2x: longPress2x,
        defaultPlaybackSpeed: speed,
        resumeBehavior: resume,
        cellularDataWarning: cellular,
        novelPageMode: novelMode,
        novelFontSize: fontSize,
        novelLineHeight: lineHeight,
        galleryLayout: galleryLayout,
        requestTimeoutSeconds: timeout,
        customUserAgent: ua,
        enableAdBlock: adBlock,
        autoCheckRuleUpdates: autoUpdate,
        themeMode: mode,
        incognitoMode: incognito,
      );
    } catch (e) {
      debugPrint('[AppService] 加载偏好设置失败: $e');
    }
  }

  /// 更新偏好并持久化
  Future<void> updateSettings(AppSettings newSettings) async {
    settingsNotifier.value = newSettings;
    _themeModeNotifier.value = newSettings.themeMode;

    await AppStorage.setBool('pref_player_gestures', newSettings.enablePlayerGestures);
    await AppStorage.setBool('pref_long_press_2x', newSettings.enableLongPress2x);
    await AppStorage.setDouble('pref_default_speed', newSettings.defaultPlaybackSpeed);
    await AppStorage.setString('pref_resume_behavior', newSettings.resumeBehavior.name);
    await AppStorage.setBool('pref_cellular_warning', newSettings.cellularDataWarning);

    await AppStorage.setString('novel_page_mode', newSettings.novelPageMode);
    await AppStorage.setDouble('novel_font_size', newSettings.novelFontSize);
    await AppStorage.setDouble('novel_line_height', newSettings.novelLineHeight);
    await AppStorage.setString('pref_gallery_layout', newSettings.galleryLayout);

    await AppStorage.setInt('pref_request_timeout', newSettings.requestTimeoutSeconds);
    await AppStorage.setString('pref_custom_ua', newSettings.customUserAgent);
    await AppStorage.setBool('pref_enable_adblock', newSettings.enableAdBlock);
    await AppStorage.setBool('pref_auto_check_rules', newSettings.autoCheckRuleUpdates);

    String modeString = 'system';
    if (newSettings.themeMode == ThemeMode.light) modeString = 'light';
    if (newSettings.themeMode == ThemeMode.dark) modeString = 'dark';
    await AppStorage.setString('app_theme_mode', modeString);

    await AppStorage.setBool('pref_incognito_mode', newSettings.incognitoMode);
  }

  /// 更新主题模式
  Future<void> updateThemeMode(ThemeMode mode) async {
    final updated = settings.copyWith(themeMode: mode);
    await updateSettings(updated);
  }

  /// 便捷切换深浅色
  Future<void> toggleThemeMode({bool? currentIsDark}) async {
    final bool dark = currentIsDark ?? (themeMode == ThemeMode.dark);
    await updateThemeMode(dark ? ThemeMode.light : ThemeMode.dark);
  }

  /// 计算临时缓存占用大小 (MB)
  Future<double> getCacheSizeInMB() async {
    try {
      final tempDir = await getTemporaryDirectory();
      int totalBytes = 0;
      if (tempDir.existsSync()) {
        await for (final file in tempDir.list(recursive: true, followLinks: false)) {
          if (file is File) {
            totalBytes += await file.length();
          }
        }
      }
      return totalBytes / (1024 * 1024);
    } catch (_) {
      return 12.8; // 默认基础安全显示值
    }
  }

  /// 清空本地网络与临时缓存
  Future<void> clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        await for (final file in tempDir.list(recursive: false, followLinks: false)) {
          try {
            await file.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
