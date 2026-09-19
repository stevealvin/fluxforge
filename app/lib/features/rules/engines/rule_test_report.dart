import 'dart:convert';

import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/rules/engines/rule_test_log_filter.dart';
import 'package:fluxforge/features/rules/models/rule_test_step.dart';

/// 规则调试的纯逻辑层（无状态，可纯 Dart 单测）
///
/// 承载三件此前完全依赖手工点测的事：
/// 1. 按媒体类型智能预填默认测试关键词；
/// 2. JSON 美化（沙箱返回值千奇百怪，格式化失败时降级为 toString）；
/// 3. 拼接可复制的 Markdown 诊断报告。
class RuleTestReport {
  const RuleTestReport._();

  /// 智能匹配不同媒体类型的默认推荐测试关键词
  static String defaultKeywordFor(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return '斗罗大陆';
      case 'novel':
        return '剑来';
      case 'picture':
      case 'comic':
        return '海贼王';
      case 'audio':
        return '三体';
      default:
        return '测试';
    }
  }

  /// 安全美化格式化 JSON 字符串
  static String formatJson(dynamic data) {
    if (data == null) return 'null';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (e) {
      return data.toString();
    }
  }

  /// 阶段状态的中文文案（用于 Markdown 报告）
  static String statusText(RuleTestStepStatus status) {
    switch (status) {
      case RuleTestStepStatus.success:
        return '✅ 成功';
      case RuleTestStepStatus.failed:
        return '❌ 失败';
      case RuleTestStepStatus.skipped:
        return '⏭️ 跳过';
      case RuleTestStepStatus.running:
      case RuleTestStepStatus.idle:
        return '⚪ 未执行';
    }
  }

  /// 拼接完整 Markdown 调试诊断报告
  ///
  /// [generatedAt] 由调用方传入而非内部取 `DateTime.now()`，便于单测断言与复现。
  static String buildMarkdown({
    required Rule rule,
    required String keyword,
    required DateTime generatedAt,
    required List<RuleTestStep> steps,
    required List<LogEntry> logs,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# FluxForge 规则诊断报告 (Rule Test Report)');
    buffer.writeln();
    buffer.writeln('- **规则名称**：${rule.name}');
    buffer.writeln('- **规则类型**：${rule.type}');
    buffer.writeln('- **规则版本**：v${rule.version ?? '1.0.0'}');
    buffer.writeln('- **源站基址**：${rule.baseUrl}');
    buffer.writeln('- **测试用词**：`$keyword`');
    buffer.writeln('- **生成时间**：${generatedAt.toIso8601String()}');
    buffer.writeln();
    buffer.writeln('## 流水线测试结果 (Pipeline)');
    buffer.writeln();

    for (final step in steps) {
      buffer.writeln('### ${step.title}');
      buffer.writeln('- **状态**：${statusText(step.status)} (${step.elapsedMs}ms)');
      if (step.summary != null) buffer.writeln('- **摘要**：${step.summary}');
      if (step.errorMessage != null) buffer.writeln('- **错误**：`${step.errorMessage}`');
      if (step.keyFields.isNotEmpty) {
        buffer.writeln('- **核心指标**：');
        step.keyFields.forEach((k, v) {
          buffer.writeln('  - $k: $v');
        });
      }
      buffer.writeln();
    }

    buffer.writeln('## 沙箱控制台日志输出 (Console Logs)');
    buffer.writeln('```');
    for (final log in logs) {
      buffer.writeln(RuleTestLogFilter.reportLine(log));
    }
    buffer.writeln('```');
    return buffer.toString();
  }
}
