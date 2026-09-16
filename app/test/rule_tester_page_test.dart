// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:fluxforge/models/rule.dart';
import 'package:fluxforge/views/rules/rule_tester_page.dart';
import 'package:fluxforge/core/theme/app_theme.dart';
import 'package:fluxforge/services/di.dart';
import 'package:fluxforge/services/app_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

  setUpAll(() {
    if (!getIt.isRegistered<AppService>()) {
      getIt.registerSingleton<AppService>(AppService());
    }
  });

  group('RuleTesterPage UI & Pipeline Tests', () {
    final sampleVideoRule = Rule(
      id: 'test-video-1',
      name: '极光视频测试源',
      baseUrl: 'https://video.fluxforge.org',
      type: 'video',
      author: 'FluxForge Team',
      version: '1.2.0',
      description: '高质量视频解析测试规则',
      code: '''
        defineRule({
          discovery: async (params) => {
            return {
              tabs: [{ title: '电影', url: '/movies' }, { title: '电视剧', url: '/tv' }],
              items: [{ title: '斗罗大陆第1季', url: '/detail/1001', cover: 'https://img.test/1.jpg' }]
            };
          },
          search: async (params) => {
            return [
              { title: '斗罗大陆：海神之光', url: '/detail/1001', cover: 'https://img.test/1.jpg', desc: '全魂师大会' }
            ];
          },
          detail: async (params) => {
            return {
              title: '斗罗大陆：海神之光',
              desc: '唐三小舞成神之路',
              items: [
                { name: '第1集', url: '/play/1001-1' },
                { name: '第2集', url: '/play/1001-2' }
              ]
            };
          },
          parse: async (params) => {
            return {
              url: 'https://stream.fluxforge.org/hls/1001-1.m3u8'
            };
          }
        });
      ''',
      enabled: true,
    );

    testWidgets('RuleTesterPage renders all 4 lifecycle stages with smart defaults', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: RuleTesterPage(rule: sampleVideoRule),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 验证标题栏包含规则名称、版本号与类型 Badge
      expect(find.text('规则调试 · 极光视频测试源'), findsOneWidget);
      expect(find.text('VIDEO'), findsOneWidget);
      expect(find.text('https://video.fluxforge.org'), findsOneWidget);

      // 2. 验证视频源智能预填推荐关键词
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.controller?.text, equals('斗罗大陆'));

      // 3. 验证存在 4 个阶段卡片
      expect(find.text('1. 发现/分类测试 (Discovery)'), findsOneWidget);
      expect(find.text('2. 关键字搜索测试 (Search)'), findsOneWidget);
      expect(find.text('3. 详情与选集测试 (Detail)'), findsOneWidget);
      expect(find.text('4. 直链/正文解析测试 (Parse)'), findsOneWidget);

      // 4. 验证操作按钮与沙箱控制台
      expect(find.text('开始测试'), findsOneWidget);
      expect(find.text('沙箱实时控制台 (Console)'), findsOneWidget);
    });

    testWidgets('RuleTesterPage handles pipeline execution gracefully with error capture and log output', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: RuleTesterPage(rule: sampleVideoRule),
        ),
      );
      await tester.pumpAndSettle();

      // 点击开始测试
      await tester.tap(find.text('开始测试'));
      await tester.pump();

      // 允许流水线异步执行并推进时间帧
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      // 在无 FFI C Bridge 的测试环境下，沙箱抛出平台级 DLL 加载异常被优雅捕获，UI 绝不崩溃
      expect(find.byType(RuleTesterPage), findsOneWidget);

      // 验证控制台日志面板存在（包含屏幕外懒加载区域）
      expect(find.text('沙箱实时控制台 (Console)', skipOffstage: false), findsOneWidget);
    });
  });
}

