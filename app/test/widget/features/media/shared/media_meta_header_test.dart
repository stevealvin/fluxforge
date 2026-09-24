// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/shared/media_meta_header.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

void main() {
  final rule = Rule(
    id: 7,
    name: '星云图源',
    baseUrl: 'https://example.com',
    type: 'novel',
    code: '// noop',
  );

  MediaDetailData detailData() => MediaDetailData(
    title: '测试书名',
    url: 'https://example.com/book/1',
    cover: 'https://img.example.com/cover.jpg',
    mediaType: MediaType.novel,
    rating: '8.9',
    author: '某某',
    updateTime: '2026-09-20',
    tags: const ['玄幻', '热血'],
    desc: '这是一段用于验证简介平铺展示的作品简介内容。',
  );

  /// 极简数据：右列文字远不足封面高度，用于验证操作位贴住封面下沿
  MediaDetailData minimalData() => MediaDetailData(
    title: '测试书名',
    url: 'https://example.com/book/2',
    cover: 'https://img.example.com/cover.jpg',
    mediaType: MediaType.novel,
  );

  Future<void> pumpHeader(
    WidgetTester tester, {
    MediaDetailData? data,
    Widget? bottomAction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaMetaHeader(
              data: data ?? detailData(),
              rule: rule,
              bottomAction: bottomAction,
            ),
          ),
        ),
      ),
    );
    // 封面图在测试环境取不到网络图，加载指示器是无限动画 → 不 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('评分与规则来源贴在封面角标里，不再占文字行', (WidgetTester tester) async {
    await pumpHeader(tester);

    final cover = tester.getRect(find.byType(Hero));
    expect(
      cover.contains(tester.getCenter(find.text('星云图源'))),
      isTrue,
      reason: '规则来源应贴在封面上，而不是挤在标题下方',
    );
    expect(cover.contains(tester.getCenter(find.text('8.9'))), isTrue);
  });

  testWidgets('规则来源角标：半透明底，且不带图标', (WidgetTester tester) async {
    await pumpHeader(tester);

    final badge = tester.widget<Container>(
      find
          .ancestor(of: find.text('星云图源'), matching: find.byType(Container))
          .first,
    );
    final badgeColor = (badge.decoration as BoxDecoration).color;
    expect(badgeColor?.a, lessThan(1.0), reason: '底色改为半透明，压住底图的同时透出封面');
    expect(
      find.descendant(of: find.byWidget(badge), matching: find.byType(Icon)),
      findsNothing,
      reason: '规则来源只是一个名字，不配图标',
    );
  });

  testWidgets('题材标签紧跟标题（评分/规则行已让位）', (WidgetTester tester) async {
    await pumpHeader(tester);

    final titleBottom = tester.getBottomLeft(find.text('测试书名')).dy;
    final tagTop = tester.getTopLeft(find.text('玄幻')).dy;
    expect(tagTop, greaterThan(titleBottom));
    expect(
      tagTop - titleBottom,
      lessThan(20),
      reason: '标签属于身份信息，应与标题相邻而不是被别的行隔开',
    );
  });

  testWidgets('主操作位落在右列底部，与封面下沿对齐', (WidgetTester tester) async {
    await pumpHeader(
      tester,
      data: minimalData(),
      bottomAction: FilledButton(onPressed: () {}, child: const Text('继续阅读')),
    );

    expect(
      tester.getBottomLeft(find.byType(FilledButton)).dy,
      closeTo(tester.getBottomLeft(find.byType(Hero)).dy, 1.0),
      reason: '右列不足封面高度时，操作位应贴住封面下沿（不新增行高）',
    );
  });

  testWidgets('标题收小一档（16.5）', (WidgetTester tester) async {
    await pumpHeader(tester);

    final title = tester.widget<Text>(find.text('测试书名'));
    expect(title.style?.fontSize, 16.5);
  });

  testWidgets('作品简介平铺展示：不再是卡片，且整段可展开/收起', (WidgetTester tester) async {
    await pumpHeader(tester);

    expect(find.text('作品简介'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MediaMetaHeader),
        matching: find.byType(AppCard),
      ),
      findsNothing,
      reason: '简介直接铺在页面上，不再包一层卡片',
    );

    await tester.tap(find.text('作品简介'));
    await tester.pump();
    expect(find.text('收起'), findsOneWidget);
  });
}
