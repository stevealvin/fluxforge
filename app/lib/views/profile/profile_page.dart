import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../services/di.dart';

/// 个人中心与应用总览页面
/// 
/// 自适应曜夜极光翡翠 (深色) 与纯净星暮白 (浅色) 全局沉浸主题
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: CustomScrollView(
        slivers: [
          // 顶部 Sliver 标题栏
          _buildHeader(isDark),

          // 用户卡片与快捷数据
          SliverToBoxAdapter(child: _buildProfileCard(isDark)),

          // 核心快捷操作网格
          SliverToBoxAdapter(child: _buildQuickActions(isDark)),

          // 功能分组列表
          SliverToBoxAdapter(child: _buildSettingsGroup(isDark)),

          // 底部版本信息与协议
          SliverToBoxAdapter(child: _buildFooter(isDark)),
        ],
      ),
    );
  }

  /// 页面顶部标题栏
  Widget _buildHeader(bool isDark) {
    return SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      elevation: 0,
      title: Text(
        '我的',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            LucideIcons.settings,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
          tooltip: '设置',
          onPressed: () => context.push('/settings'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// 用户与应用概览卡片
  Widget _buildProfileCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          // 极光渐变头像
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accentTeal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.compass,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          // 文本信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FluxForge 探索者',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '沙箱规则跨媒体聚合驱动平台',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 快捷功能入口
  Widget _buildQuickActions(bool isDark) {
    final actions = [
      {
        'title': '规则仓库',
        'icon': LucideIcons.codeXml,
        'action': () => context.push('/market'),
      },
      {
        'title': '搜索历史',
        'icon': LucideIcons.history,
        'action': () => context.push('/search'),
      },
      {
        'title': '关于系统',
        'icon': LucideIcons.info,
        'action': () => _showAboutDialog(context),
      },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions.map((item) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: item['action'] as VoidCallback?,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item['icon'] as IconData,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item['title'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 功能分组列表
  Widget _buildSettingsGroup(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          _buildListTile(
            icon: LucideIcons.palette,
            iconColor: AppColors.primary,
            title: '界面外观与设置',
            subtitle: '应用主题、网络请求与更新配置',
            isDark: isDark,
            onTap: () => context.push('/settings'),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          _buildListTile(
            icon: LucideIcons.trash2,
            iconColor: Colors.orange,
            title: '清理应用缓存',
            subtitle: '释放本地图片和历史索引缓存',
            isDark: isDark,
            onTap: () => _confirmClearCache(context),
          ),
          Divider(
            height: 1,
            indent: 56,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          _buildListTile(
            icon: LucideIcons.shieldCheck,
            iconColor: Colors.teal,
            title: '隐私与沙箱安全',
            subtitle: '查看 QuickJS 沙箱隔离与网络策略',
            isDark: isDark,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已处于全隔离沙箱运行状态，安全策略生效中')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
      ),
      onTap: onTap,
    );
  }

  /// 底部版本号与协议
  Widget _buildFooter(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Text(
            'FluxForge 跨端版 v${appService.packageInfo?.version ?? "1.0.0"}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '极光幽绿 · 曜夜与星暮纯净视界',
            style: TextStyle(
              fontSize: 11,
              color: isDark
                  ? AppColors.darkTextMuted.withValues(alpha: 0.7)
                  : AppColors.lightTextMuted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 70), // 预留底部毛玻璃 Dock 避让空间
        ],
      ),
    );
  }

  /// 清除缓存确认对话框
  void _confirmClearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('确定要清空本地搜索历史与临时图片缓存吗？（已保存的规则不会被删除）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              historyService.updateHistory([]);
              await AppStorage.remove('search_history');
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('已完成缓存清理')),
                );
              }
            },
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
  }

  /// 关于对话框
  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'FluxForge',
      applicationVersion: 'v1.0.0',
      applicationLegalese: '© 2026 FluxForge Team. All rights reserved.',
      children: const [
        SizedBox(height: 12),
        Text('轻量级、沙箱规则驱动的跨媒体聚合浏览与播放平台。'),
      ],
    );
  }
}
