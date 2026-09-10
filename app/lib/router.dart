import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import 'models/rule.dart';
import 'views/browser/browser_page.dart';
import 'views/detail/media_detail_page.dart';
import 'views/market/market_page.dart';
import 'views/profile/card_gallery_page.dart';
import 'views/profile/favorites_page.dart';
import 'views/profile/settings_page.dart';
import 'views/rules/rule_detail_page.dart';
import 'views/rules/rule_discovery_page.dart';
import 'views/search/search_page.dart';
import 'views/shell/shell_page.dart';
import 'views/splash/splash_page.dart';

/// 全局 GoRouter 统一路由配置
final GoRouter router = GoRouter(
  initialLocation: '/splash',
  routes: <RouteBase>[
    // 启动闪屏页
    GoRoute(
      path: '/splash',
      builder: (BuildContext context, GoRouterState state) {
        return const SplashPage();
      },
    ),

    // 主页面外壳 (承载底部毛玻璃导航与三大核心业务 Tab)
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const ShellPage();
      },
      routes: [
        // 内置浏览器
        GoRoute(
          path: 'web',
          builder: (BuildContext context, GoRouterState state) {
            return BrowserPage(
              url: state.uri.queryParameters['url'] ?? '',
              title: state.uri.queryParameters['title'],
            );
          },
        ),

        // 全局跨源搜索
        GoRoute(
          path: 'search',
          builder: (BuildContext context, GoRouterState state) {
            final extra = state.extra as Map<String, dynamic>?;
            return SearchPage(
              initialKeyword: extra?['keyword']?.toString() ?? state.uri.queryParameters['keyword'],
              targetRule: extra?['rule'] as Rule?,
            );
          },
        ),

        // 规则发现列表
        GoRoute(
          path: 'rule_discovery',
          builder: (BuildContext context, GoRouterState state) {
            final extra = state.extra;
            Rule? rule;
            if (extra is Rule) {
              rule = extra;
            } else if (extra is Map) {
              final r = extra['rule'];
              if (r is Rule) {
                rule = r;
              } else if (r is Map) {
                rule = Rule.fromJson(Map<String, dynamic>.from(r));
              }
            }

            if (rule == null) {
              return const Scaffold(
                body: Center(child: Text('未指定有效规则')),
              );
            }

            return RuleDiscoveryPage(
              rule: rule,
            );
          },
        ),

        // 规则内容详情
        GoRoute(
          path: 'rule_detail',
          builder: (BuildContext context, GoRouterState state) {
            final extra = state.extra is Map ? (state.extra as Map) : null;
            final ruleData = extra?['rule'];
            Rule? rule;
            if (ruleData is Rule) {
              rule = ruleData;
            } else if (ruleData is Map) {
              rule = Rule.fromJson(Map<String, dynamic>.from(ruleData));
            }

            return RuleDetailPage(
              title: extra?['title']?.toString() ?? '',
              url: extra?['url']?.toString() ?? '',
              cover: extra?['cover']?.toString() ?? '',
              rule: rule,
            );
          },
        ),

        // 媒体播放与详情分发
        GoRoute(
          path: 'detail',
          builder: (BuildContext context, GoRouterState state) {
            final extra = state.extra as Map<String, dynamic>?;
            return MediaDetailPage(
              type: extra?['type']?.toString() ?? 'movie',
              url: extra?['url']?.toString(),
              title: extra?['title']?.toString() ?? '媒体详情',
              cover: extra?['cover']?.toString(),
            );
          },
        ),

        // 系统设置
        GoRoute(
          path: 'settings',
          builder: (BuildContext context, GoRouterState state) {
            return const SettingsPage();
          },
        ),

        // 规则市场
        GoRoute(
          path: 'market',
          builder: (BuildContext context, GoRouterState state) {
            return const MarketPage();
          },
        ),

        // 卡片设计系统视觉展廊
        GoRoute(
          path: 'card_gallery',
          builder: (BuildContext context, GoRouterState state) {
            return const CardGalleryPage();
          },
        ),

        // 我的收藏与智能追更
        GoRoute(
          path: 'favorites',
          builder: (BuildContext context, GoRouterState state) {
            return const FavoritesPage();
          },
        ),
      ],
    ),
  ],
);
