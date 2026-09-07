import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'pages/rule/rule_detail.dart';
import 'pages/rule/rule_discovery.dart';

import 'pages/app.dart';
import 'pages/detail/detail_page.dart';
import 'pages/search/search_page.dart';
import 'pages/market/market_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/splash.dart';
import 'pages/web/web_page.dart';

final GoRouter router = GoRouter(
  initialLocation: '/splash',
  routes: <RouteBase>[
    GoRoute(
      path: '/splash',
      builder: (BuildContext context, GoRouterState state) {
        return const SplashPage();
      },
    ),
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const AppPage();
      },
      routes: [
        GoRoute(
          path: '/web',
          builder: (BuildContext context, GoRouterState state) {
            return WebPage(
              url: state.uri.queryParameters['url'] ?? '',
              title: state.uri.queryParameters['title'] ?? '',
            );
          },
        ),
        GoRoute(
          path: '/search',
          builder: (BuildContext context, GoRouterState state) {
            return SearchPage();
          },
        ),
        GoRoute(
          path: '/rule_discovery',
          builder: (BuildContext context, GoRouterState state) {
            return RuleDiscoveryPage(
              rule: (state.extra as Map<String, dynamic>)['rule'] ?? '',
            );
          },
        ),
        GoRoute(
          path: '/rule_detail',
          builder: (BuildContext context, GoRouterState state) {
            return RuleDetailPage(
              title: (state.extra as Map<String, dynamic>)['title'] ?? '',
              href: (state.extra as Map<String, dynamic>)['href'] ?? '',
              cover: (state.extra as Map<String, dynamic>)['cover'] ?? '',
              rule: (state.extra as Map<String, dynamic>)['rule'] ?? '',
            );
          },
        ),
        GoRoute(
          path: '/detail',
          builder: (BuildContext context, GoRouterState state) {
            return DetailPage(
              type: 'movie',
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (BuildContext context, GoRouterState state) {
            return SettingsPage();
          },
        ),
        GoRoute(
          path: '/market',
          builder: (BuildContext context, GoRouterState state) {
            return const MarketPage();
          },
        ),
      ],
    ),
  ],
);
