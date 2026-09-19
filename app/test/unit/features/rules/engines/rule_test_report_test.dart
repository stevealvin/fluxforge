import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/rules/engines/rule_test_report.dart';
import 'package:fluxforge/features/rules/models/rule_test_step.dart';

void main() {
  final rule = Rule(
    id: 1,
    name: '极光影视源',
    baseUrl: 'https://example.com',
    type: 'video',
    code: '',
  );

  group('defaultKeywordFor', () {
    test('按媒体类型智能预填推荐词', () {
      expect(RuleTestReport.defaultKeywordFor('video'), equals('斗罗大陆'));
      expect(RuleTestReport.defaultKeywordFor('novel'), equals('剑来'));
      expect(RuleTestReport.defaultKeywordFor('picture'), equals('海贼王'));
      expect(RuleTestReport.defaultKeywordFor('comic'), equals('海贼王'));
      expect(RuleTestReport.defaultKeywordFor('audio'), equals('三体'));
      expect(RuleTestReport.defaultKeywordFor('未知类型'), equals('测试'));
    });

    test('大小写不敏感', () {
      expect(RuleTestReport.defaultKeywordFor('VIDEO'), equals('斗罗大陆'));
    });
  });

  group('formatJson', () {
    test('正常对象美化输出两空格缩进', () {
      final out = RuleTestReport.formatJson({'a': 1});
      expect(out, contains('\n  "a": 1'));
    });

    test('null 返回字符串 null，无法编码时降级为 toString', () {
      expect(RuleTestReport.formatJson(null), equals('null'));
      // 循环引用对象无法 JSON 编码，必须降级而不是抛异常
      final cyclic = <String, dynamic>{};
      cyclic['self'] = cyclic;
      expect(RuleTestReport.formatJson(cyclic), contains('self'));
    });
  });

  test('statusText 覆盖全部阶段状态', () {
    expect(RuleTestReport.statusText(RuleTestStepStatus.success), contains('成功'));
    expect(RuleTestReport.statusText(RuleTestStepStatus.failed), contains('失败'));
    expect(RuleTestReport.statusText(RuleTestStepStatus.skipped), contains('跳过'));
    expect(RuleTestReport.statusText(RuleTestStepStatus.idle), contains('未执行'));
    expect(RuleTestReport.statusText(RuleTestStepStatus.running), contains('未执行'));
  });

  test('buildMarkdown 输出规则元信息 / 阶段结果 / 沙箱日志三段', () {
    final step = RuleTestStep(
      type: RuleTestStepType.search,
      title: '2. 关键字搜索测试 (Search)',
      subtitle: '检索测试',
      status: RuleTestStepStatus.success,
      elapsedMs: 128,
      summary: '命中 10 条',
      keyFields: {'命中条目数': '10 条'},
    );
    final failed = RuleTestStep(
      type: RuleTestStepType.parse,
      title: '4. 直链解析测试 (Parse)',
      subtitle: '解析测试',
      status: RuleTestStepStatus.failed,
      errorMessage: 'boom',
    );

    final logs = [
      LogEntry(
        time: DateTime(2026, 1, 1),
        level: 'ERROR',
        tag: 'Rule: 极光影视源',
        message: '网络超时',
      ),
    ];

    final report = RuleTestReport.buildMarkdown(
      rule: rule,
      keyword: '斗罗大陆',
      generatedAt: DateTime(2026, 1, 1, 10),
      steps: [step, failed],
      logs: logs,
    );

    expect(report, contains('# FluxForge 规则诊断报告'));
    expect(report, contains('极光影视源'));
    expect(report, contains('`斗罗大陆`'));
    expect(report, contains('2026-01-01T10:00:00.000'));
    expect(report, contains('2. 关键字搜索测试 (Search)'));
    expect(report, contains('(128ms)'));
    expect(report, contains('命中条目数: 10 条'));
    expect(report, contains('`boom`'));
    expect(report, contains('[ERROR] Rule: 极光影视源: 网络超时'));
    // 未声明版本时兜底 v1.0.0
    expect(report, contains('v1.0.0'));
  });
}
