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
/// 顺序即 [PageView] 与 `NavigationBar.destinations` 的下标顺序：
/// 发现 0 / 收藏 1 / 规则 2 / 站点 3 / 我的 4。
///
/// 只把需要**按名字引用**的下标抽成常量，其余下标只在本文件内按顺序使用：
/// 写死数字在中间插入 Tab 时会静默跳错页（此前"在发现之后插入收藏、
/// 规则从 1 变成 2"就属于这种情况），而没人引用的常量只是死代码。
class _ShellTab {
  const _ShellTab._();

  /// 初始 Tab：启动即「发现」
  static const int discover = 0;
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
                const ProfilePage(),
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
