import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/models/rule_search_status.dart';
import 'package:fluxforge/features/search/widgets/search_source_filter_bar.dart';

/// 检索范围控制栏的两种形态
///
/// 核心契约：**筛选入口在「搜索前」就必须可达**。
/// 「只搜索影视类型」这类需求必须在发起检索前表达 —— 搜完再过滤已经晚了，
/// 所以类型筛选入口不能只在「已有结果」时才出现，否则用户根本没地方设置它。
void main() {
  Rule rule(String name, String type) =>
      Rule(name: name, baseUrl: 'https://example.com', type: type, code: '');

  RuleSearchStatus status(String name, String type, int count) =>
      RuleSearchStatus(rule: rule(name, type), isSearching: false)..count = count;

  Future<void> pumpBar(
    WidgetTester tester, {
    required List<RuleSearchStatus> statuses,
    bool hasKindFilter = false,
    String kindLabel = '全部',
    bool isLoading = false,
    VoidCallback? onOpenFilter,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          // 检索中该栏会带 AppLoading（转圈头像），停表以便断言稳定
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SearchSourceFilterBar(
              isDark: false,
              statuses: statuses,
              totalCount: 6,
              displayCount: 6,
              selectedRule: null,
              isLoading: isLoading,
              isGridView: true,
              onRuleSelected: (_) {},
              onToggleView: (_) {},
              onOpenFilter: onOpenFilter ?? () {},
              hasKindFilter: hasKindFilter,
              kindLabel: kindLabel,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('搜索前（还没发起检索）', () {
    testWidgets('显示当前检索范围，且筛选入口可达', (tester) async {
      var opened = 0;
      await pumpBar(
        tester,
        statuses: const [],
        hasKindFilter: true,
        kindLabel: '影视',
        onOpenFilter: () => opened++,
      );

      expect(
        find.text('仅搜索「影视」类型的规则源'),
        findsOneWidget,
        reason: '搜索前要让用户看清「这一搜会搜哪些源」',
      );
      expect(find.byIcon(Ionicons.optionsOutline), findsOneWidget);

      await tester.tap(find.byIcon(Ionicons.optionsOutline));
      expect(
        opened,
        1,
        reason: '筛选入口必须在搜索前就能打开，否则用户没地方去设「只搜影视」',
      );
    });

    testWidgets('未设置类型时提示搜索全部类型', (tester) async {
      await pumpBar(tester, statuses: const []);

      expect(find.text('搜索全部类型的规则源'), findsOneWidget);
    });

    testWidgets('不显示「已汇聚 0 条」这类无意义的状态行', (tester) async {
      await pumpBar(tester, statuses: const []);

      expect(find.textContaining('已汇聚'), findsNothing);
      expect(find.text('列表排版'), findsNothing);
    });
  });

  group('搜索后', () {
    testWidgets('切换为来源胶囊并显示状态行，筛选入口仍在行尾', (tester) async {
      await pumpBar(
        tester,
        statuses: [status('极光影视', 'video', 3), status('星辰书库', 'novel', 3)],
      );

      expect(find.text('全部 (6)'), findsOneWidget);
      expect(find.text('极光影视 (3)'), findsOneWidget);
      expect(find.text('星辰书库 (3)'), findsOneWidget);
      expect(find.text('已汇聚 6 条检索结果'), findsOneWidget);

      // 搜索结果出来后，范围提示让位给来源胶囊
      expect(find.text('搜索全部类型的规则源'), findsNothing);
      // 但筛选入口不能跟着消失
      expect(find.byIcon(Ionicons.optionsOutline), findsOneWidget);
    });

    testWidgets('检索中：状态行提示剩余源数', (tester) async {
      await pumpBar(
        tester,
        statuses: [RuleSearchStatus(rule: rule('极光影视', 'video'))],
        isLoading: true,
      );

      expect(find.textContaining('正在并发检索各源数据'), findsOneWidget);
    });
  });
}
