import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/discover/discover_page.dart';
import 'package:fluxforge/features/library/favorites/favorites_page.dart';
import 'package:fluxforge/features/profile/profile_page.dart';
import 'package:fluxforge/features/rules/pages/rules_page.dart';
import 'package:fluxforge/features/sites/sites_page.dart';

/// 底部导航各 Tab 的下标
///
/// 抽成常量是因为该下标会被跨组件引用（「我的」页资产卡的「我的规则」要跳到规则 Tab），
/// 而写死数字时**在中间插入一个 Tab 就会静默跳错页** —— 本次正是在「发现」之后插入
/// 「收藏」，规则从 1 变成 2，编译器对此不会有任何提示。
class _ShellTab {
  const _ShellTab._();

  /// 顺序即 [PageView] 与 `NavigationBar.destinations` 的下标顺序：
  /// 发现 0 / 收藏 1 / 规则 2 / 站点 3 / 我的 4
  ///
  /// 只把**被跨组件引用**的两个留成常量：其余下标没有外部引用方，摆在列表顺序里
  /// 即可 —— 多写只会得到无人使用的死常量。
  static const int discover = 0;
  static const int rules = 2;
}

/// FluxForge 应用顶层外壳宿主 (ShellPage)
/// 承载全局沉浸式微光氛围底色、三维页面切换以及 Apple 级毛玻璃底部导航栏
class ShellPage extends HookWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pageController = usePageController();
    final selectedIndex = useState(_ShellTab.discover);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void goTo(int index) {
      selectedIndex.value = index;
      pageController.jumpToPage(index);
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, data) {},
      child: Scaffold(
        extendBody: true, // 关键配置：允许列表内容向下延伸并穿透到底部毛玻璃下方
        body: Stack(
          children: [
            // 顶部极光微光环境氛围渐变
            Align(
              alignment: Alignment.topLeft,
              child: Opacity(
                opacity: isDark ? 0.25 : 0.45,
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height * 0.4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.5),
                        Theme.of(context).colorScheme.surface
                            .withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            // 主标签页面视图 (发现 / 收藏 / 规则 / 站点 / 我的)
            PageView(
              physics: const NeverScrollableScrollPhysics(),
              controller: pageController,
              onPageChanged: (index) {
                selectedIndex.value = index;
              },
              children: [
                const DiscoverPage(),
                const FavoritesPage(),
                const RulesPage(),
                const SitesPage(),
                // 「我的」页需注入切页回调，以支持资产卡「我的规则」直达规则 Tab
                ProfilePage(onSwitchToRules: () => goTo(_ShellTab.rules)),
              ],
            ),
          ],
        ),
        // 高级高斯模糊毛玻璃底部导航栏
        bottomNavigationBar: RepaintBoundary(
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBg.withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.72),
                ),
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  selectedIndex: selectedIndex.value,
                  onDestinationSelected: goTo,
                  animationDuration: const Duration(milliseconds: 300),
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Ionicons.compassOutline, size: 22),
                      selectedIcon: Icon(
                        Ionicons.compassOutline,
                        size: 24,
                        color: AppColors.primary,
                      ),
                      label: '发现',
                    ),
                    const NavigationDestination(
                      icon: Icon(Ionicons.bookmarkOutline, size: 22),
                      selectedIcon: Icon(
                        Ionicons.bookmarkOutline,
                        size: 24,
                        color: AppColors.primary,
                      ),
                      label: '收藏',
                    ),
                    const NavigationDestination(
                      icon: Icon(Ionicons.codeSlashOutline, size: 22),
                      selectedIcon: Icon(
                        Ionicons.codeSlashOutline,
                        size: 24,
                        color: AppColors.primary,
                      ),
                      label: '规则',
                    ),
                    const NavigationDestination(
                      icon: Icon(Ionicons.globeOutline, size: 22),
                      selectedIcon: Icon(
                        Ionicons.globeOutline,
                        size: 24,
                        color: AppColors.primary,
                      ),
                      label: '站点',
                    ),
                    const NavigationDestination(
                      icon: Icon(Ionicons.personOutline, size: 22),
                      selectedIcon: Icon(
                        Ionicons.personOutline,
                        size: 24,
                        color: AppColors.primary,
                      ),
                      label: '我的',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
