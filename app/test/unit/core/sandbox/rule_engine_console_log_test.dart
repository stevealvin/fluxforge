import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';

void main() {
  testWidgets('Rule console.log is dispatched to AppLogger with proper rule tag', (WidgetTester tester) async {
    RuleEngine.setCurrentRunningRuleNameForTest('极光测试规则');

    // 模拟 JS 端回传的日志结构 (如: console.log('发现列表'))
    RuleEngine.handleConsoleLogForTest(['INFO', '发现列表']);
    expect(AppLogger.getLogs().any((l) => l.tag == 'Rule: 极光测试规则' && l.message == '发现列表' && l.level == 'INFO'), isTrue);

    // 模拟多参数回传
    RuleEngine.handleConsoleLogForTest(['WARN', '分类加载超时', '正在重试']);
    expect(AppLogger.getLogs().any((l) => l.tag == 'Rule: 极光测试规则' && l.message == '分类加载超时 正在重试' && l.level == 'WARN'), isTrue);

    // 模拟 JSON 字符串格式回传
    RuleEngine.handleConsoleLogForTest('["ERROR", "网络连接异常 502"]');
    expect(AppLogger.getLogs().any((l) => l.tag == 'Rule: 极光测试规则' && l.message == '网络连接异常 502' && l.level == 'ERROR'), isTrue);
  });
}
