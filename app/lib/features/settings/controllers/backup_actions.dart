import 'package:fluxforge/app/di/di.dart';

/// 备份 / 还原的「接线层」：把用户动作翻译成服务调用，并组装面向用户的文案
///
/// 之所以独立成层：备份面板是**纯 UI**（只收集输入 + 展示结果），服务调用与结果文案
/// 不应写在 Widget 里 —— 否则面板无法脱离 DI 测试。
/// 面板侧以「默认接线 + 可注入」的方式使用这两个入口
/// （与 `ChapterContentPipeline(parseRule: …)`、`RuleTestActions` 同一模式）。
///
/// 服务入口 `backupService` 定义在 `app/di/di.dart`。

/// 导出全量备份包（失败由调用方捕获并提示）
Future<void> exportBackupData() => backupService.exportBackup();

/// 按指定策略还原备份文本，返回**面向用户的提示文案**
///
/// 成功时附带各类目导入数量，失败时直接返回服务给出的原因。
Future<String> restoreBackupFromText({
  required String jsonStr,
  required bool merge,
}) async {
  final result = await backupService.restoreBackup(
    jsonStr: jsonStr,
    merge: merge,
  );
  if (!result.success) return result.message;
  return '${result.message}：规则+${result.rulesImported}，收藏+${result.favoritesImported}，'
      '搜索历史+${result.historyImported}，观看进度+${result.playHistoryImported}';
}
