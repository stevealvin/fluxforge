import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/router/app_routes.dart';
import 'package:fluxforge/app/router/route_args.dart';
import 'package:fluxforge/features/browser/adblock_rules_page.dart';
import 'package:fluxforge/features/browser/browser_page.dart';
import 'package:fluxforge/features/library/downloads/download_manager_page.dart';
import 'package:fluxforge/features/library/favorites/favorites_page.dart';
import 'package:fluxforge/features/library/history/history_center_page.dart';
import 'package:fluxforge/features/media/shared/media_detail_page.dart';
import 'package:fluxforge/features/rules/pages/market_page.dart';
import 'package:fluxforge/features/rules/pages/rule_catalog_page.dart';
import 'package:fluxforge/features/rules/pages/rule_tester_page.dart';
import 'package:fluxforge/features/search/search_page.dart';
import 'package:fluxforge/features/settings/logs_page.dart';
import 'package:fluxforge/features/settings/settings_page.dart';
import 'package:fluxforge/features/shell/shell_page.dart';
import 'package:fluxforge/features/splash/splash_page.dart';

/// 全局路由监听器 (供 AuraPlayer 等多媒体组件实现 RouteAware 生命周期自治)
/// 泛型显式约束为 `PageRoute<void>`，仅监听真正的页面级导航压栈，自动过滤 Dialog/BottomSheet/Drawer 等局部弹窗 PopupRoute
final RouteObserver<PageRoute<void>> appRouteObserver =
    RouteObserver<PageRoute<void>>();

/// 全局 GoRouter 统一路由配置
///
/// **传参约定**：所有需要携带数据的跳转一律通过 `route_args.dart` 的类型化参数类传递
/// （配合 `app_navigator.dart` 的 `BuildContext` 扩展），注册端统一调用各参数的 `tryParse`
/// 做集中解析与容错，不再直接读取 `extra` 字典的魔法键。
final GoRouter router = GoRouter(
  initialLocation: AppRoutes.splash,
  observers: [appRouteObserver],
  routes: <RouteBase>[
    // 启动闪屏页
    GoRoute(
      path: AppRoutes.splash,
      builder: (BuildContext context, GoRouterState state) =>
          const SplashPage(),
    ),

    // 主页面外壳 (承载底部毛玻璃导航与三大核心业务 Tab)
    GoRoute(
      path: AppRoutes.home,
      builder: (BuildContext context, GoRouterState state) => const ShellPage(),
      routes: [
        // 内置浏览器 (url / title 走 query 参数)
        GoRoute(
          path: AppRoutes.browserSegment,
          builder: (BuildContext context, GoRouterState state) {
            return BrowserPage(
              url: state.uri.queryParameters['url'] ?? '',
              title: state.uri.queryParameters['title'],
              enableAdBlock: appService.settingsNotifier.value.enableAdBlock,
            );
          },
        ),

        // 全局跨源搜索
        GoRoute(
          path: AppRoutes.searchSegment,
          builder: (BuildContext context, GoRouterState state) {
            final args = SearchArgs.tryParse(state.extra);
            return SearchPage(
              initialKeyword:
                  args?.keyword ?? state.uri.queryParameters['keyword'],
              targetRule: args?.rule,
            );
          },
        ),

        // 规则发现列表
        GoRoute(
          path: AppRoutes.ruleDiscoverySegment,
          builder: (BuildContext context, GoRouterState state) {
            final rule = RuleArgs.tryParse(state.extra);
            if (rule == null) {
              return const Scaffold(body: Center(child: Text('未指定有效规则')));
            }
            return RuleCatalogPage(rule: rule);
          },
        ),

        // 规则多阶段调试与测试 (类开源阅读调试器)
        GoRoute(
          path: AppRoutes.ruleTestSegment,
          builder: (BuildContext context, GoRouterState state) {
            final rule = RuleArgs.tryParse(state.extra);
            if (rule == null) {
              return const Scaffold(body: Center(child: Text('未指定有效规则进行测试')));
            }
            return RuleTesterPage(rule: rule);
          },
        ),

        // 规则内容详情 (统一调度引擎)
        GoRoute(
          path: AppRoutes.ruleDetailSegment,
          builder: (BuildContext context, GoRouterState state) {
            final args =
                RuleDetailArgs.tryParse(state.extra) ??
                const RuleDetailArgs(title: '', url: '');
            return MediaDetailPage(
              title: args.title,
              url: args.url,
              cover: args.cover,
              rule: args.rule,
            );
          },
        ),

        // 媒体播放与详情分发 (统一调度引擎)
        GoRoute(
          path: AppRoutes.mediaDetailSegment,
          builder: (BuildContext context, GoRouterState state) {
            final args =
                MediaDetailArgs.tryParse(state.extra) ??
                const MediaDetailArgs(title: '媒体详情', url: '');
            return MediaDetailPage(
              type: args.type,
              url: args.url,
              title: args.title,
              cover: args.cover,
              rule: args.rule,
            );
          },
        ),

        // 系统设置
        GoRoute(
          path: AppRoutes.settingsSegment,
          builder: (BuildContext context, GoRouterState state) =>
              const SettingsPage(),
        ),

        // 沙箱运行与系统诊断日志中心
        GoRoute(
          path: AppRoutes.logsSegment,
          builder: (BuildContext context, GoRouterState state) =>
              const LogsPage(),
        ),

        // 规则市场
        GoRoute(
          path: AppRoutes.marketSegment,
          builder: (BuildContext context, GoRouterState state) =>
              const MarketPage(),
        ),

        // 我的收藏与智能追更
        GoRoute(
          path: AppRoutes.favoritesSegment,
          builder: (BuildContext context, GoRouterState state) =>
              const FavoritesPage(),
        ),

        // 历史管理中心 (观看/阅读历史 + 搜索足迹)
        GoRoute(
          path: AppRoutes.historySegment,
          builder: (BuildContext context, GoRouterState state) =>
              const HistoryCenterPage(),
        ),

        // 离线下载管理 (小说全本 / 漫画整部)
        GoRoute(
          path: AppRoutes.downloadsSegment,
          builder: (BuildContext context, GoRouterState state) =>
              const DownloadManagerPage(),
        ),

        // 广告拦截规则管理
        GoRoute(
          path: AppRoutes.adblockSegment,
          builder: (BuildContext context, GoRouterState state) =>
              const AdBlockRulesPage(),
        ),
      ],
    ),
  ],
);
