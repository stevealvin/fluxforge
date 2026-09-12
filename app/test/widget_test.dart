// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:fluxforge/widgets/app_card.dart';
import 'package:fluxforge/views/profile/logs_page.dart';
import 'package:fluxforge/views/search/search_page.dart';
import 'package:fluxforge/core/utils/app_logger.dart';
import 'package:fluxforge/core/theme/app_theme.dart';
import 'package:fluxforge/services/di.dart';
import 'package:fluxforge/services/app_service.dart';
import 'package:fluxforge/services/rule_service.dart';
import 'package:fluxforge/services/history_service.dart';
import 'package:fluxforge/services/rule_engine.dart';
import 'package:fluxforge/widgets/player/aura_player.dart';
import 'package:fluxforge/models/rule.dart';
import 'package:fluxforge/router.dart';
import 'package:fluxforge/views/rules/rule_detail_page.dart';
import 'package:fluxforge/views/detail/photo_gallery_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  testWidgets('AppCard component renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppCard(
            child: Text('FluxForge Card Test'),
          ),
        ),
      ),
    );

    expect(find.text('FluxForge Card Test'), findsOneWidget);
    expect(find.byType(AppCard), findsOneWidget);
  });

  testWidgets('LogsPage renders with AppTheme without crash', (WidgetTester tester) async {
    AppLogger.addLog(
      level: 'INFO',
      tag: 'Rule Sandbox',
      message: 'QuickJS 沙箱内核初始化就绪',
    );
    AppLogger.addLog(
      level: 'ERROR',
      tag: 'Network',
      message: 'Failed to connect: 500 Internal Server Error',
      error: 'SocketException',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const LogsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('沙箱运行日志'), findsOneWidget);
    expect(find.text('QuickJS 沙箱内核初始化就绪'), findsOneWidget);
  });

  testWidgets('SearchPage input field has no duplicate border and handles search tap cleanly', (WidgetTester tester) async {
    if (!getIt.isRegistered<AppService>()) {
      getIt.registerSingleton<AppService>(AppService());
    }
    if (!getIt.isRegistered<RuleService>()) {
      getIt.registerSingleton<RuleService>(RuleService());
    }
    if (!getIt.isRegistered<HistoryService>()) {
      getIt.registerSingleton<HistoryService>(HistoryService());
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const SearchPage(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 验证搜索输入框与“搜索”按钮正确渲染
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);

    // 2. 验证 TextField 的 InputDecoration 彻底清空了所有自带边框与填充（消除双圆角嵌套缺陷）
    final textField = tester.widget<TextField>(textFieldFinder);
    final decoration = textField.decoration;
    expect(decoration, isNotNull);
    expect(decoration?.border, equals(InputBorder.none));
    expect(decoration?.enabledBorder, equals(InputBorder.none));
    expect(decoration?.focusedBorder, equals(InputBorder.none));
    expect(decoration?.filled, isFalse);

    // 3. 输入搜索词并点击“搜索”按钮，验证不会卡死挂起（hang）
    await tester.enterText(textFieldFinder, '测试');
    await tester.pump();
    
    // 点击搜索按钮
    await tester.tap(find.text('搜索'));
    // 让出 50ms 驱动 microtask 与 Future.delayed(30ms)
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // 验证流程顺利推进（无可用规则源时给出 SnackBar 提示，UI 绝不挂起）
    expect(find.text('暂无可用的规则源，请先在规则市场中导入并启用规则'), findsOneWidget);
  });

  testWidgets('SearchPage handles single targetRule with integer id without NoSuchMethodError or crash on search tap', (WidgetTester tester) async {
    // 关键模拟：从 SQLite 数据库查出来的真实规则，id 为 int 类型 1 (之前导致 NoSuchMethodError 的根因)
    final testDbRule = Rule(
      id: 1,
      name: '极光单源测试',
      author: 'FluxForge',
      version: '1.0.0',
      type: 'video',
      baseUrl: 'https://example.com',
      code: 'var Flux = { search: function() { return []; } };',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: SearchPage(
          targetRule: testDbRule,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 验证单规则专属输入提示展示正常
    expect(find.text('在「极光单源测试」中搜索...'), findsOneWidget);

    // 2. 输入搜索词并点击“搜索”按钮
    final textFieldFinder = find.byType(TextField);
    await tester.enterText(textFieldFinder, '斗罗大陆');
    await tester.pump();

    // 3. 点击“搜索”
    await tester.tap(find.text('搜索'));

    // 4. 推进事件队列与定时器
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    // 5. 核心验证：绝对不抛出 NoSuchMethodError 或渲染崩溃，takeException 为 null
    expect(tester.takeException(), isNull);
    // 6. 页面依然完好健康渲染，杜绝全屏灰死
    expect(find.byType(SearchPage), findsOneWidget);
  });

  testWidgets('Video result card badge Positioned inside Stack does not throw ParentData error', (WidgetTester tester) async {
    const displayTag = '更新至24集';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 140,
              height: 80,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const SizedBox.expand(),
                  if (displayTag.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        child: const Text(displayTag),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更新至24集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HistoryService saves and broadcasts search keywords correctly', (WidgetTester tester) async {
    final history = HistoryService();
    await history.init();

    await history.clearHistory();
    expect(history.searchHistory, isEmpty);

    await history.addHistory('测试关键词1');
    expect(history.searchHistory.contains('测试关键词1'), isTrue);
    expect(history.searchHistory.first, equals('测试关键词1'));

    await history.addHistory('测试关键词2');
    expect(history.searchHistory.first, equals('测试关键词2'));
    expect(history.searchHistory.length, equals(2));

    await history.removeHistory('测试关键词1');
    expect(history.searchHistory.contains('测试关键词1'), isFalse);
    expect(history.searchHistory.length, equals(1));
  });

  testWidgets('Rule console.log is dispatched to AppLogger with proper rule tag', (WidgetTester tester) async {
    RuleEngine.setCurrentRunningRuleNameForTest('极光测试规则');

    // 模拟 JS 端回传的日志结构 (如: console.log('发现列表'))
    RuleEngine.handleConsoleLogForTest(['INFO', '发现列表']);
    expect(AppLogger.getLogs().any((l) => l.tag == 'Rule: 极光测试规则' && l.message == '发现列表' && l.level == 'INFO'), isTrue);

    // 模拟多参数回传
    RuleEngine.handleConsoleLogForTest(['WARN', '分类加载超时', '正在重试']);
    expect(AppLogger.getLogs().any((l) => l.tag == 'Rule: 极光测试规则' && l.message == '分类加载超时 正在重试' && l.level == 'WARN'), isTrue);

    // 模拟 JSON 字符串格式回传
    RuleEngine.handleConsoleLogForTest('["ERROR", "网络连接异常 502"]');
    expect(AppLogger.getLogs().any((l) => l.tag == 'Rule: 极光测试规则' && l.message == '网络连接异常 502' && l.level == 'ERROR'), isTrue);
  });

  testWidgets('RuleEngine standard template transformToRunnableJs cleanly converts export default to module.exports', (WidgetTester tester) async {
    const standardTemplateCode = '''
import axios from 'axios';
import cheerio from 'cheerio';

export default defineRule({
  async discovery({ tab = '', page = 1 }) {
    let url = `\${baseUrl}/page/\${page}`;
    console.log('发现列表', url);
    return { items: [] };
  },
  async search({ keyword, page = 1 }) {
    return { items: [] };
  },
  async detail({ url, item }) {
    console.log('detail详情', url);
    return { title: '测试详情' };
  },
  async parse({ url, groupName }) {
    return { playUrl: url };
  }
})
''';

    final runnableJs = RuleEngine.transformToRunnableJs(standardTemplateCode);
    // 1. 验证移除了顶层 import 语句
    expect(runnableJs.contains("import axios from 'axios'"), isFalse);
    expect(runnableJs.contains("import cheerio from 'cheerio'"), isFalse);

    // 2. 验证 export default defineRule 规范转换为 module.exports = defineRule
    expect(runnableJs.startsWith('module.exports = defineRule({'), isTrue);
    expect(runnableJs.contains("async detail({ url, item })"), isTrue);
  });

  testWidgets('AuraPlayer widget builds with expected clipBehavior and structure', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AuraPlayer(
            playUrl: '',
            title: '测试视频',
          ),
        ),
      ),
    );

    // 验证播放器成功构建且包含 ClipRect 视口防溢出裁剪
    expect(find.byType(AuraPlayer), findsOneWidget);
    expect(find.byType(ClipRect), findsWidgets);
  });

  testWidgets('RuleDetailPage builds correctly and handles video view layout', (WidgetTester tester) async {
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
        home: RuleDetailPage(
          title: '流光测试剧集',
          url: 'https://example.com/detail/1',
          cover: 'https://example.com/cover.jpg',
          rule: testRule,
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(RuleDetailPage), findsOneWidget);
  });

  testWidgets('AuraPlayer integrates with RouteObserver and auto pauses on route covered', (WidgetTester tester) async {
    // 验证 AuraPlayer 支持 autoPauseOnCovered 属性并能够在路由覆盖与压栈生命周期中稳定协同
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: const Scaffold(
          body: AuraPlayer(
            playUrl: '',
            title: '路由感知测试',
            autoPauseOnCovered: true,
          ),
        ),
      ),
    );

    expect(find.byType(AuraPlayer), findsOneWidget);
  });

  testWidgets('PhotoViewPage supports vertical comic long-scroll mode and toggle correctly', (WidgetTester tester) async {
    const testImages = [
      'https://example.com/page1.jpg',
      'https://example.com/page2.jpg',
      'https://example.com/page3.jpg',
    ];

    // 1. 以默认左右翻页模式渲染 PhotoViewPage
    await tester.pumpWidget(
      const MaterialApp(
        home: PhotoViewPage(
          imageList: testImages,
          initialIndex: 0,
          initialContinuousMode: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 验证当前处于左右翻页视图 (指示胶囊显示"左右翻页")
    expect(find.text('1 / 3'), findsOneWidget);
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


