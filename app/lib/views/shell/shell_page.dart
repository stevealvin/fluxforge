import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../discover/discover_page.dart';
import '../profile/profile_page.dart';
import '../rules/rules_page.dart';

/// FluxForge 应用顶层外壳宿主 (ShellPage)
/// 承载全局沉浸式微光氛围底色、三维页面切换以及 Apple 级毛玻璃底部导航栏
class ShellPage extends HookWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pageController = usePageController();
    final selectedIndex = useState(0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            // 主标签页面视图 (精简收敛为三大核心场景: 发现 / 规则 / 我的)
            PageView(
              physics: const NeverScrollableScrollPhysics(),
              controller: pageController,
              onPageChanged: (index) {
                selectedIndex.value = index;
              },
              children: const [
                DiscoverPage(),
                RulesPage(),
                ProfilePage(),
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
                onDestinationSelected: (value) {
                  selectedIndex.value = value;
                  pageController.jumpToPage(value);
                },
                animationDuration: const Duration(milliseconds: 300),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(LucideIcons.compass, size: 22),
                    selectedIcon: Icon(LucideIcons.compass, size: 24, color: AppColors.primary),
                    label: '发现',
                  ),
                  NavigationDestination(
                    icon: Icon(LucideIcons.code, size: 22),
                    selectedIcon: Icon(LucideIcons.code, size: 24, color: AppColors.primary),
                    label: '规则',
                  ),
                  NavigationDestination(
                    icon: Icon(LucideIcons.user, size: 22),
                    selectedIcon: Icon(LucideIcons.user, size: 24, color: AppColors.primary),
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
