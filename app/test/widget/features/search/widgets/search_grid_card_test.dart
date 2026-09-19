import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/models/search_result.dart';
import 'package:fluxforge/features/search/widgets/search_grid_card.dart';

void main() {
  Rule ruleOf(String type) => Rule(
        id: 1,
        name: '极光影视源',
        baseUrl: 'https://example.com',
        type: type,
        code: '',
      );

  NormalizedSearchResult itemOf(String type) => NormalizedSearchResult.fromMap(
        {
          'title': '流光网格内容',
          'desc': '双列瀑布流卡片描述',
          'badge': '高清 4K',
          'cover': 'https://example.com/cover.jpg',
        },
        ruleOf(type),
      );

  testWidgets('视频源走 16:9 横版网格卡片并渲染角标与来源', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 160,
              child: SearchGridCard(item: itemOf('video'), isDark: true, onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SearchVideoGridCard), findsOneWidget);
    expect(find.byType(SearchPosterGridCard), findsNothing);
    expect(find.text('流光网格内容'), findsOneWidget);
    expect(find.text('高清 4K'), findsOneWidget);
    expect(find.text('极光影视源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非视频源走全幅海报网格卡片', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 200,
              child: SearchGridCard(item: itemOf('picture'), isDark: false, onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SearchPosterGridCard), findsOneWidget);
    expect(find.byType(SearchVideoGridCard), findsNothing);
    expect(find.text('流光网格内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
