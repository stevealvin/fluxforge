import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/history_service.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/search_page.dart';

void main() {
  testWidgets('SearchPage input field has no duplicate border and handles search tap cleanly', (WidgetTester tester) async {
    if (!getIt.isRegistered<AppService>()) {
      getIt.registerSingleton<AppService>(AppService());
    }
    if (!getIt.isRegistered<RuleService>()) {
      getIt.registerSingleton<RuleService>(RuleService());
    }
    if (!getIt.isRegistered<HistoryService>()) {
      getIt.registerSingleton<HistoryService>(HistoryService());
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 验证搜索输入框与“搜索”按钮正确渲染
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);

    // 2. 验证 TextField 的 InputDecoration 彻底清空了所有自带边框与填充（消除双圆角嵌套缺陷）
    final textField = tester.widget<TextField>(textFieldFinder);
    final decoration = textField.decoration;
    expect(decoration, isNotNull);
    expect(decoration?.border, equals(InputBorder.none));
    expect(decoration?.enabledBorder, equals(InputBorder.none));
    expect(decoration?.focusedBorder, equals(InputBorder.none));
    expect(decoration?.filled, isFalse);

    // 3. 输入搜索词并点击“搜索”按钮，验证不会卡死挂起（hang）
    await tester.enterText(textFieldFinder, '测试');
    await tester.pump();

    // 点击搜索按钮
    await tester.tap(find.text('搜索'));
    // 让出 50ms 驱动 microtask 与 Future.delayed(30ms)
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // 验证流程顺利推进（无可用规则源时给出 SnackBar 提示，UI 绝不挂起）
    expect(find.text('暂无可用的规则源，请先在规则市场中导入并启用规则'), findsOneWidget);
  });

  testWidgets('SearchPage handles single targetRule with integer id without NoSuchMethodError or crash on search tap', (WidgetTester tester) async {
    // 关键模拟：从 SQLite 数据库查出来的真实规则，id 为 int 类型 1 (之前导致 NoSuchMethodError 的根因)
    final testDbRule = Rule(
      id: 1,
      name: '极光单源测试',
      author: 'FluxForge',
      version: '1.0.0',
      type: 'video',
      baseUrl: 'https://example.com',
      code: 'var Flux = { search: function() { return []; } };',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: SearchPage(
          targetRule: testDbRule,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 验证单规则专属输入提示展示正常
    expect(find.text('在「极光单源测试」中搜索...'), findsOneWidget);

    // 2. 输入搜索词并点击“搜索”按钮
    final textFieldFinder = find.byType(TextField);
    await tester.enterText(textFieldFinder, '斗罗大陆');
    await tester.pump();

    // 3. 点击“搜索”
    await tester.tap(find.text('搜索'));

    // 4. 推进事件队列与定时器
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // 5. 核心验证：绝对不抛出 NoSuchMethodError 或渲染崩溃，takeException 为 null
    expect(tester.takeException(), isNull);
    // 6. 页面依然完好健康渲染，杜绝全屏灰死
    expect(find.byType(SearchPage), findsOneWidget);
  });
}
