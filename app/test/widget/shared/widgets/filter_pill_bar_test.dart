import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/shared/widgets/filter_pill_bar.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<FilterPillItem> items,
  required String selectedKey,
  ValueChanged<String>? onSelected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: FilterPillBar(
          items: items,
          selectedKey: selectedKey,
          onSelected: onSelected ?? (_) {},
        ),
      ),
    ),
  );
}

/// 胶囊容器的描边集合（只看筛选条内部，避免把页面其它 Container 算进来）
List<Border> _pillBorders(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(FilterPillBar),
        matching: find.byType(Container),
      ),
    )
    .map((c) => (c.decoration as BoxDecoration?)?.border)
    .whereType<Border>()
    .toList();

void main() {
  const items = [
    FilterPillItem(key: 'all', label: '全部', count: 5),
    FilterPillItem(key: 'video', label: '影视', count: 2),
    FilterPillItem(key: 'comic', label: '漫画', count: 0),
  ];

  testWidgets('渲染全部胶囊并带各自数量，数量为 0 也列出来', (WidgetTester tester) async {
    await _pump(tester, items: items, selectedKey: 'all');

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('影视'), findsOneWidget);
    expect(find.text('漫画'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // 0 数量仍然列出（降淡）：否则用户要点进去才发现那一类是空的
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('点击胶囊把 selectedKey 对应的键回调出去', (WidgetTester tester) async {
    String? picked;
    await _pump(
      tester,
      items: items,
      selectedKey: 'all',
      onSelected: (key) => picked = key,
    );

    await tester.tap(find.text('影视'));
    await tester.pump();

    expect(picked, 'video');
  });

  testWidgets('每个胶囊都保留描边占位，同一时刻只有一个是主色', (WidgetTester tester) async {
    await _pump(tester, items: items, selectedKey: 'comic');

    final borders = _pillBorders(tester);
    expect(
      borders.length,
      3,
      reason: '未选中也要有透明描边占位，否则切到选中态时会跳尺寸',
    );
    expect(
      borders.where((b) => b.top.color == AppColors.primary).length,
      1,
      reason: '选中态只应有一个主色描边',
    );
    expect(
      borders.where((b) => b.top.color == Colors.transparent).length,
      2,
    );
  });
}
