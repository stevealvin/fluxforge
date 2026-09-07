import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<MinePage> {
  // App使用数据
  final usageData = UsageData(
    appVersion: '2.1.0',
    lastUpdate: '2024-01-15',
    totalUsageDays: 45,
    favoriteCount: 12,
    createdCount: 8,
  );

  // 功能分组
  final List<FeatureGroup> featureGroups = [
    FeatureGroup(
      title: '实用工具',
      items: [
        FeatureItem(
          icon: Icons.bookmark,
          title: '规则管理',
          subtitle: '整理书签和分类',
          route: '/bookmarks',
          color: Colors.orange,
        ),
        FeatureItem(
          icon: Icons.share_arrival_time,
          title: '导入/导出',
          subtitle: '备份和恢复数据',
          route: '/backup',
          color: Colors.teal,
        ),
      ],
    ),
    FeatureGroup(
      title: '应用设置',
      items: [
        FeatureItem(
          icon: Icons.settings,
          title: '通用设置',
          subtitle: '主题、语言等',
          route: '/settings',
          color: Colors.grey,
        ),
        FeatureItem(
          icon: Icons.brush,
          title: '主题定制',
          subtitle: '自定义界面外观',
          route: '/theme',
          color: Colors.pink,
        ),
        FeatureItem(
          icon: Icons.help,
          title: '使用指南',
          subtitle: '新手教程和FAQ',
          route: '/guide',
          color: Colors.blueGrey,
        ),
        FeatureItem(
          icon: Icons.info,
          title: '关于应用',
          subtitle: '版本信息和协议',
          route: '/about',
          color: Colors.brown,
        ),
      ],
    ),
  ];

  final List<Map<String, dynamic>> quickActions = [
    {
      'title': '规则中心',
      'icon': LucideIcons.codeXml,
      'route': '/rules',
    },
    {
      'title': '收藏',
      'icon': Icons.favorite_outline_rounded,
      'route': '/favorites',
    },
    {
      'title': '最近浏览',
      'icon': Icons.list_alt_sharp,
      'route': '/favorites',
    },
    {
      'title': '下载',
      'icon': Icons.cloud_download_outlined,
      'route': '/downloads',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部标题和状态
          _buildHeaderSection(),
          
          // 快捷操作
          _buildQuickActions(),
          
          // 功能列表
          _buildFeatureList(),
          
          // 底部信息
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      title: const Text(
        '我的',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: .spaceAround,
          children: quickActions.map((item) {
            return GestureDetector(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(item['icon'], size: 28, color: Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item['title'],
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );  
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFeatureList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final group = featureGroups[index];
          return _buildFeatureGroup(group);
        },
        childCount: featureGroups.length,
      ),
    );
  }

  Widget _buildFeatureGroup(FeatureGroup group) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Text(
              group.title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: group.items.map((item) => _buildFeatureItem(item)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(FeatureItem item) {
    return ListTile(
      minTileHeight: 36,
      minVerticalPadding: .minPositive,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(item.icon, color: item.color, size: 22),
      ),
      title: Text(
        item.title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        item.subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.count != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.count.toString(),
                style: TextStyle(
                  color: item.color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: Colors.grey.shade400,
          ),
        ],
      ),
      onTap: () {
        context.push(item.route);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildFooter() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          children: [
            Text(
              '${usageData.appVersion} • 上次更新 ${usageData.lastUpdate}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _onPrivacyPolicy,
                  child: const Text('隐私政策'),
                ),
                Container(
                  width: 1,
                  height: 12,
                  color: Colors.grey.shade300,
                ),
                TextButton(
                  onPressed: _onUserAgreement,
                  child: const Text('用户协议'),
                ),
                Container(
                  width: 1,
                  height: 12,
                  color: Colors.grey.shade300,
                ),
                TextButton(
                  onPressed: _onClearCache,
                  child: const Text('清除缓存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onPrivacyPolicy() {
    debugPrint('隐私政策');
  }

  void _onUserAgreement() {
    debugPrint('用户协议');
  }

  void _onClearCache() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存数据吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              // 执行清除缓存
              Navigator.pop(context);
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}

// 数据模型
class UsageData {
  final String appVersion;
  final String lastUpdate;
  final int totalUsageDays;
  final int favoriteCount;
  final int createdCount;

  UsageData({
    required this.appVersion,
    required this.lastUpdate,
    required this.totalUsageDays,
    required this.favoriteCount,
    required this.createdCount,
  });
}

class FeatureGroup {
  final String title;
  final List<FeatureItem> items;

  FeatureGroup({required this.title, required this.items});
}

class FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? count;
  final String route;
  final Color color;

  FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.count,
    required this.route,
    required this.color,
  });
}

class QuickAction {
  final IconData icon;
  final String title;
  final String route;
  final Color color;

  QuickAction({
    required this.icon,
    required this.title,
    required this.route,
    required this.color,
  });
}

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: CustomScrollView(
//         slivers: [
//           SliverAppBar(
//             automaticallyImplyLeading: false,
//             scrolledUnderElevation: 0,
//             elevation: 0,
//             toolbarHeight: kTextTabBarHeight + 20,
//             title: const Text(
//               '我的',
//               style: TextStyle(
//                 height: 2.8,
//                 fontSize: 17,
//                 fontWeight: FontWeight.bold,
//                 fontFamily: 'Jura-Bold',
//               ),
//             ),
//             actions: [
//               IconButton(
//                 onPressed: () {},
//                 icon: Icon(Icons.dark_mode_outlined, size: 22),
//               ),
//               IconButton(
//                 onPressed: () {
//                   context.push('/settings');
//                 },
//                 icon: const Icon(Icons.settings_outlined),
//               ),
//               const SizedBox(width: 10),
//             ],
//           ),
//           SliverGrid.list(
//             gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//               crossAxisCount: 4,
//             ),
//             children: <Widget>[
//               Container(color: Colors.red),
//               Container(color: Colors.green),
//               Container(color: Colors.blue),
//               Container(color: Colors.yellow),
//               Container(color: Colors.orange),
//               Container(color: Colors.purple),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }
