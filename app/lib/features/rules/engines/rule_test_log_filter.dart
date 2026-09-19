import 'package:fluxforge/core/logging/app_logger.dart';

/// 沙箱控制台日志的过滤与格式化（纯逻辑，可纯 Dart 单测）
///
/// 过滤规则此前内联在页面中，只能靠手工点测验证；抽出后可用构造好的
/// [LogEntry] 列表直接断言「只保留本规则相关 + 本轮开始之后产生的日志」。
class RuleTestLogFilter {
  const RuleTestLogFilter._();

  /// 过滤获取与当前规则相关的沙箱控制台日志
  ///
  /// 命中条件：标签完全等于 `Rule: <规则名>`；或在本轮测试开始之后产生，
  /// 且标签属于规则域（含 'Rule' 或为 'Rule Sandbox'）。
  static List<LogEntry> forRule(
    List<LogEntry> allLogs, {
    required String ruleTag,
    DateTime? startTime,
  }) {
    return allLogs.where((l) {
      if (l.tag == ruleTag) return true;
      if (startTime != null && l.time.isAfter(startTime)) {
        return l.tag.contains('Rule') || l.tag == 'Rule Sandbox';
      }
      return false;
    }).toList();
  }

  /// 报告用单行文本：`[LEVEL] tag: message`
  static String reportLine(LogEntry log) => '[${log.level}] ${log.tag}: ${log.message}';

  /// 控制台复制用单行文本：`[LEVEL] message`
  static String consoleLine(LogEntry log) => '[${log.level}] ${log.message}';
}
