import 'package:fluxforge/core/storage/app_storage.dart';

/// 漫画 / 图集阅读方式的持久化偏好
///
/// 键名与读写收敛到这一处：设置页与漫画阅读器**读写同一把键**，
/// 因此「设置里选的默认方式」与「阅读器里临时切换」不会各说各话
/// （此前设置页那行「图集与画廊默认视图」写的是 `pref_gallery_layout`，
/// 而阅读器读写的是另一把键 —— 改了等于没改）。
class ComicReaderPreferences {
  const ComicReaderPreferences._();

  /// 长条连读模式的持久化键（false = 左右翻页）
  static const String continuousModeKey = 'comic_reader_continuous_mode';

  /// 读取「长条连读」偏好；未持久化或读取失败返回 `null`（保持调用方默认）
  static Future<bool?> loadContinuousMode() async {
    try {
      return await AppStorage.getBool(continuousModeKey);
    } catch (_) {
      // 存储不可用时静默按默认阅读方式继续，不阻断打开阅读器
      return null;
    }
  }

  /// 持久化「长条连读」偏好
  static Future<void> saveContinuousMode(bool continuous) async {
    try {
      await AppStorage.setBool(continuousModeKey, continuous);
    } catch (_) {}
  }
}
