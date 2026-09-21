import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/novel/novel_detail_view.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

void main() {
  setUp(() {
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
  });

  testWidgets('暗色模式下简介卡与目录章节卡必须是深色实体底，页面内不得出现亮色背景', (
    WidgetTester tester,
  ) async {
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
          body: SingleChildScrollView(
            child: NovelDetailView(data: data, fallbackTitle: '暗夜测试小说'),
          ),
        ),
      ),
    );
    await tester.pump();

    // 1. 暗色主题确实生效（isDark 判定的前提）
    final context = tester.element(find.byType(NovelDetailView));
    expect(Theme.of(context).brightness, Brightness.dark);

    // 2. 简介卡 + 目录章节卡：都应显式使用深色实体底
    final cardColors = tester
        .widgetList<AppCard>(find.byType(AppCard))
        .map((card) => card.color)
        .toList();
    expect(
      cardColors.where((color) => color == AppColors.darkCard).length,
      greaterThanOrEqualTo(3),
      reason: '简介卡与 2 个目录章节卡应使用 darkCard，实际：$cardColors',
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
}
