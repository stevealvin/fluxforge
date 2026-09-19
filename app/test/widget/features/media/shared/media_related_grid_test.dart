import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/shared/media_related_grid.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

void main() {
  testWidgets('MediaRelatedGrid renders with AppCard.flat, structured title and count', (WidgetTester tester) async {
    const testRelated = [
      MediaRelatedItem(
        title: '推荐电影 A',
        url: 'https://example.com/movie_a',
        cover: 'https://example.com/cover_a.jpg',
        badge: '超清 4K',
        desc: '这是一部科幻巨作',
      ),
      MediaRelatedItem(
        title: '推荐电影 B',
        url: 'https://example.com/movie_b',
        cover: 'https://example.com/cover_b.jpg',
        desc: '冒险题材',
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaRelatedGrid(
              related: testRelated,
              isWide: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 1. 验证标题栏格式：主标题与弱化数量计数分离
    expect(find.text('相关推荐'), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);

    // 2. 验证推荐项使用 AppCard 包裹
    expect(find.byType(AppCard), findsNWidgets(2));

    // 3. 验证推荐项标题与角标
    expect(find.text('推荐电影 A'), findsOneWidget);
    expect(find.text('超清 4K'), findsOneWidget);
    expect(find.text('这是一部科幻巨作'), findsOneWidget);
    expect(find.text('推荐电影 B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
