import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/shared/media_detail_page.dart';

void main() {
  testWidgets('MediaDetailPage builds correctly and handles video view layout', (WidgetTester tester) async {
    final testRule = Rule(
      id: 'test_video_rule',
      name: '测试影视规则',
      type: 'video',
      baseUrl: 'https://example.com',
      code: '''
module.exports = {
  detail: async () => ({
    title: '流光测试剧集',
    rating: '9.8',
    desc: '这是一部充满未来科技感的赛博朋克流光视界巨作。',
    tags: ['科幻', '机战'],
    items: [
      { title: '第01集', url: 'https://example.com/ep1.mp4' },
      { title: '第02集', url: 'https://example.com/ep2.mp4' },
    ]
  })
};
''',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: MediaDetailPage(
          title: '流光测试剧集',
          url: 'https://example.com/detail/1',
          cover: 'https://example.com/cover.jpg',
          rule: testRule,
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(MediaDetailPage), findsOneWidget);

    // 排空详情页初始化时规则引擎的 500ms 延迟初始化定时器，避免 fake_async 报挂起
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('MediaDetailPage top bar has no bottom border line and renders dark theme title cleanly', (WidgetTester tester) async {
    // 媒体详情页涉及断点续播，需确保消费历史服务已在测试容器中注册
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
    // 排空定时器后详情抓取会真正走到规则服务，需一并注册，避免 GetIt 未注册异常
    if (!getIt.isRegistered<AppService>()) {
      getIt.registerSingleton<AppService>(AppService());
    }
    if (!getIt.isRegistered<RuleService>()) {
      getIt.registerSingleton<RuleService>(RuleService());
    }

    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const MediaDetailPage(
          title: '暗夜测试流媒体',
          url: 'https://example.com/video/1',
        ),
      ),
    );
    await tester.pump();

    // 验证包含标题文字 (顶栏与正文标题)
    final titleWidgets = find.text('暗夜测试流媒体');
    expect(titleWidgets, findsWidgets);

    // 验证顶栏标题不设置死硬编码颜色，由主题自动自适应接管
    final Text topBarText = tester.widget<Text>(titleWidgets.first);
    expect(topBarText.style?.color, isNull);

    // 验证顶栏 Container 没有下边框（消除顶栏与视频播放器之间的多余分割线）
    final topBarContainerFinder = find.byWidgetPredicate((widget) {
      if (widget is Container && widget.decoration is BoxDecoration) {
        final decoration = widget.decoration as BoxDecoration;
        return decoration.border == null && widget.child is Row;
      }
      return false;
    });
    expect(topBarContainerFinder, findsWidgets);
    expect(tester.takeException(), isNull);

    // 排空规则引擎 500ms 延迟初始化定时器，避免 fake_async 报挂起
    await tester.pump(const Duration(milliseconds: 600));
  });
}
