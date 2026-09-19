import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/comic/reader/comic_reader_page.dart';

void main() {
  testWidgets('ComicReaderPage supports vertical comic long-scroll mode and toggle correctly', (WidgetTester tester) async {
    const testImages = [
      'https://example.com/page1.jpg',
      'https://example.com/page2.jpg',
      'https://example.com/page3.jpg',
    ];

    // 1. 以默认左右翻页模式渲染 ComicReaderPage
    await tester.pumpWidget(
      const MaterialApp(
        home: ComicReaderPage(
          imageList: testImages,
          initialIndex: 0,
          initialContinuousMode: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 验证当前处于左右翻页视图 (指示胶囊显示"左右翻页")
    expect(find.text('1 / 3 页'), findsOneWidget);
    expect(find.text('左右翻页'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);

    // 2. 点击切换胶囊，切换至纵向长漫画长卷模式
    await tester.tap(find.text('左右翻页'));
    await tester.pump(const Duration(milliseconds: 300));

    // 验证长漫画模式切换成功 (胶囊变为"长漫画"，并且出现全屏 ListView)
    expect(find.text('长漫画'), findsOneWidget);
    final listViewFinder = find.byType(ListView);
    expect(listViewFinder, findsOneWidget);

    final listView = tester.widget<ListView>(listViewFinder);
    expect(listView.padding, equals(EdgeInsets.zero)); // 验证零内边距铺满

    // 3. 再次点击切换回左右翻页
    await tester.tap(find.text('长漫画'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('左右翻页'), findsOneWidget);
  });
}
