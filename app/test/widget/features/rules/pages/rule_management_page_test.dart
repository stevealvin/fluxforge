// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/rules/pages/rule_management_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() async {
    if (!getIt.isRegistered<RuleService>()) {
      getIt.registerSingleton<RuleService>(RuleService());
    }
    await AppStorage.clear();
    await ruleService.saveRules([]);
    await pumpEventQueue();
  });

  Rule ruleOf({
    required String name,
    String type = 'video',
    bool enabled = true,
  }) => Rule(
    id: name,
    name: name,
    baseUrl: 'https://example.com',
    type: type,
    code: '// noop',
    enabled: enabled,
  );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const RuleManagementPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('列出全部规则（含未启用），开关反映真实状态', (WidgetTester tester) async {
    await ruleService.saveRules([
      ruleOf(name: '启用中的规则'),
      ruleOf(name: '已停用的规则', enabled: false),
    ]);

    await pumpPage(tester);

    expect(find.text('启用中的规则'), findsOneWidget);
    // 管理页必须能看到未启用的规则 —— 使用侧恰恰把它们隐藏了
    expect(find.text('已停用的规则'), findsOneWidget);

    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.length, 2);
    expect(switches[0].value, isTrue);
    expect(switches[1].value, isFalse);
    expect(find.text('启用 1 / 2'), findsOneWidget);
  });

  testWidgets('切换开关改的是规则的启用状态', (WidgetTester tester) async {
    await ruleService.saveRules([ruleOf(name: '待停用')]);

    await pumpPage(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(ruleService.rules.single.enabled, isFalse);
  });

  testWidgets('点击规则行弹出管理面板（调试测试 / 复制源站 / 删除）', (WidgetTester tester) async {
    await ruleService.saveRules([ruleOf(name: '流光规则')]);

    await pumpPage(tester);
    await tester.tap(find.text('流光规则'));
    await tester.pumpAndSettle();

    expect(find.text('规则调试与测试'), findsOneWidget);
    expect(find.text('复制源站地址'), findsOneWidget);
    expect(find.text('删除此规则'), findsOneWidget);
  });

  testWidgets('没有规则时给出空态', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(find.text('暂无本地规则'), findsOneWidget);
  });
}
