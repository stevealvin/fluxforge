import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'tabbar/discover.dart';
import 'tabbar/mine.dart';
import 'tabbar/rule.dart';
import 'market/market_page.dart';

class AppPage extends HookWidget {
  const AppPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pageController = usePageController();
    final selectedIndex = useState(0);
    
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, data) {},
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Opacity(
                opacity:
                    Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.6,
                child: Container(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                        Theme.of(context).colorScheme.surface,
                        Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.1, 0.3, 5],
                    ),
                  ),
                ),
              ),
            ),
            PageView(
              physics: const NeverScrollableScrollPhysics(),
              controller: pageController,
              onPageChanged: (index) {
                selectedIndex.value = index;
              },
              children: [
                DiscoverPage(),
                const MarketPage(),
                const RulePage(),
                const MinePage(),
              ],
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          animationDuration: const Duration(milliseconds: 300),
          selectedIndex: selectedIndex.value,
          onDestinationSelected: (value) {
            selectedIndex.value = value;
            pageController.jumpToPage(value);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: '发现',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: '市场',
            ),
            NavigationDestination(
              icon: Icon(Icons.code_rounded),
              selectedIcon: Icon(Icons.code_rounded),
              label: '规则',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
