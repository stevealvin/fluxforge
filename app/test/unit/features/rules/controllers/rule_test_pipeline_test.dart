import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/rules/controllers/rule_test_pipeline.dart';
import 'package:fluxforge/features/rules/engines/rule_test_actions.dart';
import 'package:fluxforge/features/rules/models/rule_test_step.dart';

/// 可控的沙箱动作假实现
///
/// 四个阶段各返回一个由测试手动完成的 `Completer.future`，从而稳定复现
/// 「阶段仍在途时被中止 / 被新一轮顶替」这类只靠时序才能命中的场景
/// （真机上需要精确卡在网络返回的瞬间，无法稳定复现）。
class _FakeRuleTestActions extends RuleTestActions {
  _FakeRuleTestActions();

  final Completer<dynamic> discoveryResult = Completer<dynamic>();
  final Completer<dynamic> searchResult = Completer<dynamic>();
  final Completer<dynamic> detailResult = Completer<dynamic>();
  final Completer<dynamic> parseResult = Completer<dynamic>();

  int discoveryCalls = 0;

  @override
  Future<dynamic> discovery(Rule rule) {
    discoveryCalls++;
    return discoveryResult.future;
  }

  @override
  Future<dynamic> search(Rule rule, String keyword) => searchResult.future;

  @override
  Future<dynamic> detail(Rule rule, String url, {Map<String, dynamic>? item}) =>
      detailResult.future;

  @override
  Future<dynamic> parse(Rule rule, String url) => parseResult.future;
}

Rule _buildRule() => Rule(
      id: 'pipeline-test',
      name: '流水线测试源',
      baseUrl: 'https://t.fluxforge.org',
      type: 'video',
      author: 'test',
      version: '1.0.0',
      description: '单测用规则',
      code: 'defineRule({});',
      enabled: true,
    );

List<RuleTestStep> _buildSteps() => [
      RuleTestStep(type: RuleTestStepType.discovery, title: '1. 发现', subtitle: 's'),
      RuleTestStep(type: RuleTestStepType.search, title: '2. 搜索', subtitle: 's'),
      RuleTestStep(type: RuleTestStepType.detail, title: '3. 详情', subtitle: 's'),
      RuleTestStep(type: RuleTestStepType.parse, title: '4. 解析', subtitle: 's'),
    ];

/// 让流水线的 await 链推进一轮微任务
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('RuleTestPipeline 运行轮次：中止 / 被顶替后的在途结果处置', () {
    test('中止后：在途阶段的成功结果被丢弃', () async {
      final actions = _FakeRuleTestActions();
      final steps = _buildSteps();
      var notifyCount = 0;
      final pipeline = RuleTestPipeline(
        rule: _buildRule(),
        steps: steps,
        onStepChanged: () => notifyCount++,
        actions: actions,
      );

      final running = pipeline.run('测试关键词');
      // 已发出「阶段开始」通知，正卡在沙箱调用上
      expect(steps[0].status, RuleTestStepStatus.running);
      expect(notifyCount, equals(1));

      pipeline.cancel();
      // 沙箱此刻才返回成功结果 —— 属于已作废的那一轮
      actions.discoveryResult.complete(<String, dynamic>{'tabs': [], 'items': []});
      await running;

      expect(steps[0].rawResponse, isNull, reason: '迟到结果不得写入阶段模型');
      expect(steps[0].status, RuleTestStepStatus.running,
          reason: '不得被改写成 success / failed');
      expect(notifyCount, equals(1), reason: '中止后不再产生阶段通知');
      expect(pipeline.isCancelled, isTrue);
    });

    test('中止后：在途阶段的异常同样被丢弃', () async {
      final actions = _FakeRuleTestActions();
      final steps = _buildSteps();
      final pipeline = RuleTestPipeline(
        rule: _buildRule(),
        steps: steps,
        onStepChanged: () {},
        actions: actions,
      );

      final running = pipeline.run('测试关键词');
      pipeline.cancel();
      actions.discoveryResult.completeError(Exception('沙箱超时'));
      await running;

      expect(steps[0].errorMessage, isNull, reason: '作废轮次的异常不得污染阶段状态');
      expect(steps[0].status, RuleTestStepStatus.running);
    });

    test('被新一轮顶替：旧一轮结果丢弃，新一轮照常推进', () async {
      final actions = _FakeRuleTestActions();
      final steps = _buildSteps();
      final pipeline = RuleTestPipeline(
        rule: _buildRule(),
        steps: steps,
        onStepChanged: () {},
        actions: actions,
      );

      final first = pipeline.run('旧关键词');
      expect(steps[0].status, RuleTestStepStatus.running);

      // 用户重开一轮（页面会先把阶段模型 reset 干净）。
      // 新一轮会推进到搜索阶段后停住，故此处不 await，只让微任务推进
      for (final step in steps) {
        step.reset();
      }
      unawaited(pipeline.run('新关键词'));
      expect(actions.discoveryCalls, equals(2));

      // 两轮共用同一个沙箱 Future：先到的是旧一轮，后到的属于新一轮
      actions.discoveryResult.complete(<String, dynamic>{
        'tabs': [],
        'items': [<String, dynamic>{'title': '首项', 'url': '/detail/1'}],
      });
      await first;
      await _flush();

      expect(steps[0].status, RuleTestStepStatus.success,
          reason: '新一轮应正常写入结果');
      expect(steps[0].rawResponse, isNotNull);
      expect(steps[1].status, RuleTestStepStatus.running,
          reason: '新一轮应继续推进到搜索阶段');

      // 收尾：避免测试结束时仍有未完成的沙箱调用
      pipeline.cancel();
    });

    test('未中止时四阶段照常接力，产物逐级传递（回归）', () async {
      final actions = _FakeRuleTestActions();
      final steps = _buildSteps();
      final pipeline = RuleTestPipeline(
        rule: _buildRule(),
        steps: steps,
        onStepChanged: () {},
        actions: actions,
      );

      final running = pipeline.run('关键词');

      // 阶段 1：发现 → 产出候选条目
      actions.discoveryResult.complete(<String, dynamic>{
        'tabs': [],
        'items': [<String, dynamic>{'title': '首项', 'url': '/detail/1'}],
      });
      await _flush();
      expect(steps[0].status, RuleTestStepStatus.success);

      // 阶段 2：搜索命中 → 详情目标优先取搜索结果
      actions.searchResult.complete(<dynamic>[
        <String, dynamic>{'title': '命中', 'url': '/detail/2'},
      ]);
      await _flush();
      expect(steps[1].status, RuleTestStepStatus.success);
      expect(steps[2].status, RuleTestStepStatus.running);
      expect(steps[2].requestParams?['url'], equals('/detail/2'));

      // 阶段 3：详情 → 产出章节 URL
      actions.detailResult.complete(<String, dynamic>{
        'title': '详情',
        'items': [<String, dynamic>{'title': '第1集', 'url': '/play/1'}],
      });
      await _flush();
      expect(steps[2].status, RuleTestStepStatus.success);
      expect(steps[3].status, RuleTestStepStatus.running);
      expect(steps[3].requestParams?['url'], equals('/play/1'));

      // 阶段 4：解析直链
      actions.parseResult.complete(<String, dynamic>{'url': 'https://s.test/1.m3u8'});
      await running;
      expect(steps[3].status, RuleTestStepStatus.success);
      expect(steps[3].keyFields['流媒体协议'], contains('HLS'));
    });
  });
}
