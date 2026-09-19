import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/models/search_result.dart';
import 'package:fluxforge/features/search/widgets/search_list_card.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

void main() {
  Rule ruleOf(String type) => Rule(
        id: 1,
        name: '极光影视源',
        baseUrl: 'https://example.com',
        type: type,
        code: '',
      );

  NormalizedSearchResult itemOf(String type, {int index = 0}) =>
      NormalizedSearchResult.fromMap(
        {
          'title': '流光测试内容 $index',
          'desc': '这是一部充满未来科技感的赛博朋克流光视界巨作。',
          'badge': '更新至24集',
          'cover': 'https://example.com/cover_$index.jpg',
        },
        ruleOf(type),
      );

  testWidgets('视频源走横版列表卡片，角标 Positioned 直接挂在 Stack 下不触发 ParentData 断言', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchListCard(
            item: itemOf('video'),
            isDark: true,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SearchVideoListCard), findsOneWidget);
    expect(find.byType(SearchPortraitListCard), findsNothing);
    expect(find.byType(AppCard), findsOneWidget);
    expect(find.text('流光测试内容 0'), findsOneWidget);
    expect(find.text('更新至24集'), findsOneWidget);
    expect(find.text('极光影视源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非视频源走竖版列表卡片', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchListCard(
            item: itemOf('novel'),
            isDark: false,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SearchPortraitListCard), findsOneWidget);
    expect(find.byType(SearchVideoListCard), findsNothing);
    expect(find.text('极光影视源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击卡片回抛 onTap 回调', (WidgetTester tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchListCard(
            item: itemOf('video'),
            isDark: false,
            onTap: () => tapped++,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(SearchVideoListCard));
    // 封面加载占位动画是无限循环的，不能用 pumpAndSettle（永不收敛）
    await tester.pump(const Duration(milliseconds: 100));

    expect(tapped, equals(1));
  });
}
