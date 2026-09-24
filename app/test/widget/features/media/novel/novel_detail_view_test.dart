import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/novel/novel_detail_view.dart';
import 'package:fluxforge/features/media/shared/media_meta_header.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

void main() {
  setUp(() {
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
  });

  testWidgets('暗色模式下目录章节卡必须是深色实体底，页面内不得出现亮色背景', (WidgetTester tester) async {
    final data = MediaDetailData(
      title: '暗夜测试小说',
      url: 'https://example.com/novel/1',
      cover: '',
      desc: '这是一段用于验证暗色模式底色的作品简介内容。',
      mediaType: MediaType.novel,
      chapters: [
        MediaEpisode(title: '第1章 起点', url: 'https://example.com/1'),
        MediaEpisode(title: '第2章 发展', url: 'https://example.com/2'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: AppColors.darkBg,
          // 详情视图自带「固定头部 + 目录独立滚动」的骨架，不能再套一层滚动
          // （那会让高度约束变成无限，内部的 Expanded 直接报错）
          body: NovelDetailView(data: data, fallbackTitle: '暗夜测试小说'),
        ),
      ),
    );
    await tester.pump();

    // 1. 暗色主题确实生效（isDark 判定的前提）
    final context = tester.element(find.byType(NovelDetailView));
    expect(Theme.of(context).brightness, Brightness.dark);

    // 2. 目录章节卡：应显式使用深色实体底
    final cardColors = tester
        .widgetList<AppCard>(find.byType(AppCard))
        .map((card) => card.color)
        .toList();
    expect(
      cardColors.where((color) => color == AppColors.darkCard).length,
      greaterThanOrEqualTo(2),
      reason: '2 个目录章节卡应使用 darkCard，实际：$cardColors',
    );
    // 简介已改为平铺：头部里不应再有卡片包裹
    expect(
      find.descendant(
        of: find.byType(MediaMetaHeader),
        matching: find.byType(AppCard),
      ),
      findsNothing,
      reason: '作品简介直接铺在页面上，不再包一层卡片',
    );

    // 3. 兜底扫描：暗色模式下页面内不应存在任何亮色实体背景
    final brightBackgrounds = <Color>[];
    for (final element in find.byType(Container).evaluate()) {
      final decoration = (element.widget as Container).decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        final color = decoration.color!;
        if (color.a > 0.5 && color.computeLuminance() > 0.5) {
          brightBackgrounds.add(color);
        }
      }
    }
    expect(
      brightBackgrounds,
      isEmpty,
      reason: '暗色模式下不应出现亮色实体背景，实际：$brightBackgrounds',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('目录选章：全量进滚动区，不再截断到 30 章', (WidgetTester tester) async {
    final chapters = List.generate(
      40,
      (i) => MediaEpisode(
        title: '第${i + 1}章',
        url: 'https://example.com/${i + 1}',
      ),
    );
    final data = MediaDetailData(
      title: '目录测试书',
      url: 'https://example.com/novel/2',
      cover: '',
      mediaType: MediaType.novel,
      chapters: chapters,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: NovelDetailView(data: data)),
      ),
    );
    await tester.pump();

    // 旧实现只铺前 30 章，末尾挂一个「进入阅读器查看全部」兜底入口
    expect(find.textContaining('进入阅读器查看全部'), findsNothing);

    final list = tester.widget<SliverList>(find.byType(SliverList));
    expect(
      list.delegate.estimatedChildCount,
      40,
      reason: '全量交给滚动区，由 sliver 懒加载兜住（几万章也只构建可见行）',
    );

    // 头部固定 + 目录自己滚：拖动目录时标题位置不动
    final titleBefore = tester.getTopLeft(find.text('目录测试书'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pump();
    expect(tester.getTopLeft(find.text('目录测试书')), titleBefore);
  });
}
