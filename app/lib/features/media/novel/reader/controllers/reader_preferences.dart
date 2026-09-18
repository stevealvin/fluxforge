import 'package:flutter/foundation.dart';

import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/features/media/novel/reader/models/page_turn_mode.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 已持久化的阅读偏好快照
///
/// 字段可空：**未设置过的项保持 null**，调用方据此逐项覆盖默认值，
/// 而不是把「未设置」误当作「设置为默认值」。
@immutable
class ReaderPreferencesSnapshot {
  const ReaderPreferencesSnapshot({
    this.fontSize,
    this.lineHeight,
    this.theme,
    this.pageMode,
  });

  /// 字号（px）
  final double? fontSize;

  /// 行距倍数
  final double? lineHeight;

  /// 护眼底色
  final ReaderTheme? theme;

  /// 翻页模式
  final PageTurnMode? pageMode;

  /// 是否一项都没有持久化过
  bool get isEmpty =>
      fontSize == null && lineHeight == null && theme == null && pageMode == null;
}

/// 阅读偏好持久化
///
/// 把四个偏好键的读写收敛到一处：键名与取值集中定义，杜绝字符串散落在
/// 各调用点被拼错或写错类型；读取失败时静默返回空快照，不阻断阅读。
class ReaderPreferences {
  const ReaderPreferences._();

  /// 字号（px）
  static const String fontSizeKey = 'novel_font_size';

  /// 行距倍数
  static const String lineHeightKey = 'novel_line_height';

  /// 护眼底色名（[ReaderTheme.name]）
  static const String themeKey = 'novel_theme';

  /// 翻页模式标识
  static const String pageModeKey = 'novel_page_mode';

  /// 翻页模式的持久化取值（纵向）
  static const String pageModeVertical = 'vertical';

  /// 翻页模式的持久化取值（横向）
  static const String pageModeHorizontal = 'horizontal';

  /// 读取全部阅读偏好；未持久化或读取失败时对应字段为 null
  static Future<ReaderPreferencesSnapshot> load() async {
    try {
      final savedFontSize = await AppStorage.getDouble(fontSizeKey);
      final savedLineHeight = await AppStorage.getDouble(lineHeightKey);
      final savedThemeName = await AppStorage.getString(themeKey);
      final savedPageMode = await AppStorage.getString(pageModeKey);

      return ReaderPreferencesSnapshot(
        fontSize: savedFontSize,
        lineHeight: savedLineHeight,
        theme: savedThemeName == null
            ? null
            : ReaderTheme.values.firstWhere(
                (e) => e.name == savedThemeName,
                orElse: () => ReaderTheme.parchment,
              ),
        pageMode: savedPageMode == null
            ? null
            : (savedPageMode == pageModeVertical
                ? PageTurnMode.verticalScroll
                : PageTurnMode.horizontal),
      );
    } catch (_) {
      // 存储不可用等异常静默忽略：保持默认排版继续阅读
      return const ReaderPreferencesSnapshot();
    }
  }

  static Future<void> saveFontSize(double value) =>
      AppStorage.setDouble(fontSizeKey, value);

  static Future<void> saveLineHeight(double value) =>
      AppStorage.setDouble(lineHeightKey, value);

  static Future<void> saveTheme(ReaderTheme theme) =>
      AppStorage.setString(themeKey, theme.name);

  static Future<void> savePageMode(PageTurnMode mode) => AppStorage.setString(
        pageModeKey,
        mode == PageTurnMode.verticalScroll ? pageModeVertical : pageModeHorizontal,
      );
}
