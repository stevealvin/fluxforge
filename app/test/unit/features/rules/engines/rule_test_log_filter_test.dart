import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/features/rules/engines/rule_test_log_filter.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 10);

  LogEntry entry(String tag, String message, DateTime time, {String level = 'INFO'}) =>
      LogEntry(time: time, level: level, tag: tag, message: message);

  group('forRule', () {
    test('完全命中规则标签的日志无条件保留（即使在测试开始之前）', () {
      final logs = [
        entry('Rule: 极光源', '旧日志', t0.subtract(const Duration(minutes: 5))),
      ];
      final out = RuleTestLogFilter.forRule(logs, ruleTag: 'Rule: 极光源', startTime: t0);
      expect(out.length, equals(1));
    });

    test('本轮开始后产生的规则域日志保留，域外日志丢弃', () {
      final logs = [
        entry('Rule Sandbox', '沙箱初始化', t0.add(const Duration(seconds: 1))),
        entry('Rule: 其它源', '其它源日志', t0.add(const Duration(seconds: 2))),
        entry('Network', '网络请求', t0.add(const Duration(seconds: 3))),
        entry('System', '系统日志', t0.add(const Duration(seconds: 4))),
      ];
      final out = RuleTestLogFilter.forRule(logs, ruleTag: 'Rule: 极光源', startTime: t0);
      expect(out.map((l) => l.tag).toList(), equals(['Rule Sandbox', 'Rule: 其它源']));
    });

    test('未提供起始时间时，仅保留完全命中标签的日志', () {
      final logs = [
        entry('Rule: 极光源', '本源日志', t0),
        entry('Rule Sandbox', '沙箱日志', t0),
      ];
      final out = RuleTestLogFilter.forRule(logs, ruleTag: 'Rule: 极光源');
      expect(out.length, equals(1));
      expect(out.first.message, equals('本源日志'));
    });

    test('起始时间之前的日志全部剔除', () {
      final logs = [
        entry('Rule Sandbox', '上一轮残留', t0.subtract(const Duration(seconds: 1))),
      ];
      final out = RuleTestLogFilter.forRule(logs, ruleTag: 'Rule: 极光源', startTime: t0);
      expect(out, isEmpty);
    });
  });

  test('reportLine 带标签，consoleLine 不带标签', () {
    final log = entry('Rule: 极光源', '解析完成', t0, level: 'WARN');
    expect(RuleTestLogFilter.reportLine(log), equals('[WARN] Rule: 极光源: 解析完成'));
    expect(RuleTestLogFilter.consoleLine(log), equals('[WARN] 解析完成'));
  });
}
