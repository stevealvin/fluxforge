// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/features/settings/logs_page.dart';
import 'package:fluxforge/features/search/search_page.dart';
import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/data/library/history_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/shared/widgets/player/aura_player.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/app/router/app_router.dart';
import 'package:fluxforge/features/media/shared/media_detail_page.dart';
import 'package:fluxforge/features/media/comic/reader/comic_reader_page.dart';
import 'package:fluxforge/features/media/novel/reader/novel_reader_page.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:ionicons/ionicons.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/shared/media_related_grid.dart';

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

  test('RuleEngine handles standalone defineRule with top-level comments and constants cleanly without syntax corruption', () {
    const rawJs = '''
// 这是一个包含顶部注释和常量的规则
const API_BASE = 'https://example.com';
const TIMEOUT = 5000;

defineRule({
  async discovery({ page = 1 }) {
    return { items: [] };
  }
});
''';
    final runnableJs = RuleEngine.transformToRunnableJs(rawJs);
    // 验证绝不生成非法的 module.exports = const ... 或 module.exports = // ...
    expect(runnableJs.contains('module.exports = const'), isFalse);
    expect(runnableJs.contains('module.exports = //'), isFalse);
    expect(runnableJs.contains('const API_BASE'), isTrue);
    expect(runnableJs.contains('defineRule({'), isTrue);
  });

  test('RuleEngine transformToRunnableJs cleanly handles import crypto / CryptoJS and preserves crypto execution statements', () {
    const cryptoRuleCode = '''
import axios from 'axios';
import cheerio from 'cheerio';
import crypto from 'crypto';
import CryptoJS from 'crypto-js';

export default defineRule({
  async discovery() {
    const md5Hex = crypto.createHash('md5').update('hello').digest('hex');
    const hmacHex = crypto.createHmac('sha256', 'secret_key').update('hello').digest('hex');
    const cjsMd5 = CryptoJS.MD5('hello').toString();
    return {
      md5: md5Hex,
      hmac: hmacHex,
      cjsMd5: cjsMd5
    };
  }
});
''';

    final runnableJs = RuleEngine.transformToRunnableJs(cryptoRuleCode);
    // 验证 import 语句均被干净剔除，不留语法残渣
    expect(runnableJs.contains("import crypto from 'crypto'"), isFalse);
    expect(runnableJs.contains("import CryptoJS from 'crypto-js'"), isFalse);
    // 验证核心加密调用与生命周期方法被完整保留
    expect(runnableJs.contains("crypto.createHash('md5')"), isTrue);
    expect(runnableJs.contains("crypto.createHmac('sha256'"), isTrue);
    expect(runnableJs.contains("CryptoJS.MD5('hello')"), isTrue);
    expect(runnableJs.startsWith('module.exports = defineRule({'), isTrue);
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
  });

  testWidgets('AuraPlayer supports external control via GlobalKey<AuraPlayerState> pause and play', (WidgetTester tester) async {
    final playerKey = GlobalKey<AuraPlayerState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuraPlayer(
            key: playerKey,
            playUrl: '',
            title: '受控接口测试',
          ),
        ),
      ),
    );

    expect(find.byType(AuraPlayer), findsOneWidget);
    expect(playerKey.currentState, isNotNull);

    // 验证能够成功调用公开的 pause() 与 play() 受控方法而不崩溃
    playerKey.currentState?.pause();
    expect(tester.takeException(), isNull);

    playerKey.currentState?.play();
    expect(tester.takeException(), isNull);
  });

  testWidgets('AuraPlayer does not pause on internal popup dialog, drawer or fullscreen transitions', (WidgetTester tester) async {
    late BuildContext currentContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              currentContext = ctx;
              return const AuraPlayer(
                playUrl: '',
                title: '弹窗不暂停测试',
                autoPauseOnCovered: true,
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(AuraPlayer), findsOneWidget);

    // 1. 模拟弹出对话框/设置抽屉 (属于 PopupRoute)
    showGeneralDialog(
      context: currentContext,
      pageBuilder: (dialogContext, _, _) {
        return const Center(child: Text('内部设置抽屉'));
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('内部设置抽屉'), findsOneWidget);
    // 验证播放器未崩溃或出现异常
    expect(tester.takeException(), isNull);

    // 关闭弹窗
    Navigator.of(currentContext).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('内部设置抽屉'), findsNothing);
  });

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

  testWidgets('NovelReaderPage renders chapter content, supports SelectionArea and catalog drawer cleanly', (WidgetTester tester) async {
    final testChapters = [
      const NovelChapter(
        title: '第1章 宇宙闪烁',
        content: '第一行测试小说正文，宏伟的宇宙规律向人类眨了眨眼睛。\n\n第二行测试小说正文，物理学的大厦轰然作响。',
      ),
      const NovelChapter(
        title: '第2章 科学边界',
        content: '这是第二章的测试内容。',
      ),
    ];

    // 渲染 NovelReaderPage
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookTitle: '三体测试版',
          initialChapterIndex: 0,
          chapters: testChapters,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 1. 验证包含了 SelectableText (保证文本可长按划词自由选区复制)
    expect(find.byType(SelectableText), findsWidgets);

    // 2. 验证章节标题和内容切片已正常展示，且不是“正在加载”
    expect(find.text('第1章 宇宙闪烁'), findsOneWidget);
    expect(find.textContaining('第一行测试小说正文'), findsOneWidget);

    // 3. 点击呼出控制栏面板
    await tester.tap(find.byKey(const ValueKey('reader_gesture_area')));
    await tester.pump(const Duration(milliseconds: 200));

    // 验证控制栏出现章节目录按钮 (Ionicons.reorderFourOutline)
    expect(find.byIcon(Ionicons.reorderFourOutline), findsWidgets);

    // 4. 点击目录按钮，验证左侧抽屉打开、章节列表渲染且缓存状态图标正常
    await tester.tap(find.byIcon(Ionicons.reorderFourOutline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 目录应列出后续章节；状态图标已统一为「沙盒离线下载」单一语义：
    // 未下载章节展示云端下载入口（不再出现「已缓存」对勾，避免误以为可断网阅读）
    expect(find.text('第2章 科学边界'), findsWidgets);
    expect(find.byIcon(Ionicons.cloudDownloadOutline), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage renders empty state instead of sample chapters when no chapters provided', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '空章节测试'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 严禁渲染任何示例假章节，必须展示空态引导
    expect(find.text('暂无章节内容'), findsOneWidget);
    expect(find.textContaining('科学边界'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage tap zones turn pages on sides and toggle menu in center', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      NovelChapter(title: '第2章 终点', content: '第二章正文内容。'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '分区点击测试', chapters: chapters),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 1. 点击右侧 1/3 区域：本章仅一页 → 应无缝续读下一章
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('第2章 终点'), findsWidgets);

    // 2. 点击中间 1/3 区域：应呼出控制栏（出现目录按钮）
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byIcon(Ionicons.reorderFourOutline), findsWidgets);

    // 3. 点击左侧 1/3 区域：本章第一页 → 应无缝倒序回退到上一章
    await tester.tapAt(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('第1章 起点'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage error state keeps retry button clickable without tap-zone interception', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 断链', url: 'https://example.com/broken-chapter'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '错误态测试', chapters: chapters),
      ),
    );
    // 未绑定解析规则 → 正文抓取失败，进入错误态
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('重试加载'), findsOneWidget);

    // 点击重试按钮：必须命中按钮本身，而不是被三区热层抢走变成「呼出菜单」
    await tester.tap(find.text('重试加载'));
    await tester.pump(const Duration(milliseconds: 300));

    // 控制栏未被呼出，证明错误态下全屏热层已撤除
    expect(find.byIcon(Ionicons.reorderFourOutline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage catalog order toggle flips chapter list order', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      NovelChapter(title: '第2章 发展', content: '第二章正文内容。'),
      NovelChapter(title: '第3章 终点', content: '第三章正文内容。'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '目录排序测试', chapters: chapters),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 呼出控制栏并打开章节目录（左抽屉）
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byIcon(Ionicons.reorderFourOutline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    double catalogItemTop(String title) => tester
        .getTopLeft(find.descendant(of: find.byType(Drawer), matching: find.text(title)))
        .dy;

    // 默认正序：第 1 章在第 3 章上方
    expect(catalogItemTop('第1章 起点'), lessThan(catalogItemTop('第3章 终点')));

    // 切换为倒序：第 3 章应升到最上方，按钮文案同步变更
    await tester.tap(find.text('正序'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('倒序'), findsOneWidget);
    expect(catalogItemTop('第3章 终点'), lessThan(catalogItemTop('第1章 起点')));

    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage horizontal bridge and seek synchronization does not accidentally trigger chapter retreat', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      NovelChapter(title: '第2章 发展', content: '第二章长篇正文，第一段描述。\n\n第二章第二段描述。\n\n第二章第三段描述。'),
      NovelChapter(title: '第3章 终点', content: '第三章正文内容。'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(
          bookTitle: '桥接同步测试',
          chapters: chapters,
          initialChapterIndex: 1, // 直接从第 2 章开始
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 验证初始状态正确处于第 2 章
    expect(find.text('第2章 发展'), findsWidgets);

    // 呼出控制栏
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 250));

    // 找到章内进度条并拖拽至起始端
    final sliderFinder = find.byType(Slider);
    if (sliderFinder.evaluate().isNotEmpty) {
      await tester.drag(sliderFinder.first, const Offset(-300, 0));
      await tester.pump(const Duration(milliseconds: 350));
      // 必须依然保持在第 2 章，严禁误触发章首桥接页退回第 1 章
      expect(find.text('第2章 发展'), findsWidgets);
    }

    expect(tester.takeException(), isNull);
  });

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

  testWidgets('MediaDetailPage top bar has no bottom border line and renders dark theme title cleanly', (WidgetTester tester) async {
    // 媒体详情页涉及断点续播，需确保消费历史服务已在测试容器中注册
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
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
  });
}


