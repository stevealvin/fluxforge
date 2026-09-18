import 'package:flutter/services.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/shared/widgets/setting_tile.dart';
import 'package:fluxforge/features/profile/widgets/continue_watching_row.dart';
import 'package:fluxforge/features/profile/widgets/profile_asset_grid.dart';
import 'package:fluxforge/features/profile/widgets/profile_hero.dart';

/// 个人中心页面 (我的)
///
/// 经过重新设计，从「功能入口集合」升级为「个人资产仪表盘」，按五大语义区组织：
/// ① 身份 Hero（昵称 / 沙箱状态 / 主题三态 / 设置唯一入口）
/// ② 继续观看（跨媒体消费记录横滑流，一键续播）
/// ③ 我的资产（2×2 资产卡网格：收藏 / 历史 / 规则 / 足迹）
/// ④ 数据与同步（规则市场 / 离线下载 / 缓存治理）
///
/// 数据备份还原、沙箱日志与「关于」信息已统一收敛至「设置」页，
/// 设置入口由顶部 Hero 卡右上角齿轮提供，避免同屏出现重复入口。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onSwitchTab});

  /// 切换底部导航 Tab 的回调（供「我的规则」资产卡直达规则页）
  final void Function(int index)? onSwitchTab;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// 临时缓存占用（MB），null 表示统计中或当前不可用
  double? _cacheSizeMB;

  bool _isCleaning = false;

  @override
  void initState() {
    super.initState();
    _fetchCacheSize();
  }

  /// 统计临时缓存占用（异步执行，不阻塞首帧渲染）
  Future<void> _fetchCacheSize() async {
    final size = await appService.getCacheSizeInMB();
    if (mounted) setState(() => _cacheSizeMB = size);
  }

  /// 下拉刷新：追更检测 + 缓存重算（移动端高频入口一体化）
  Future<void> _refreshAll() async {
    HapticFeedback.lightImpact();
    final updates = await favoriteService.checkUpdates();
    await _fetchCacheSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updates > 0 ? '检测到 $updates 部收藏有新更新' : '收藏进度均为最新，缓存统计已刷新',
        ),
      ),
    );
  }

  /// 仅清理临时与网络缓存（不再连带清空搜索足迹，避免误删用户资产）
  Future<void> _cleanCacheOnly() async {
    if (_isCleaning) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清理临时缓存'),
        content: const Text('将清空临时目录中的网络图片与文件缓存，不影响收藏、规则与历史记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _isCleaning = true);
    await appService.clearCache();
    await _fetchCacheSize();
    if (!mounted) return;
    setState(() => _isCleaning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清理临时与网络缓存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          color: AppColors.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              // ① 身份 Hero
              const ProfileHero(),
              const SizedBox(height: 18),

              // ② 继续观看（断点续播横滑流）
              const ContinueWatchingRow(),
              const SizedBox(height: 18),

              // ③ 我的资产（2×2 资产卡网格）
              ProfileAssetGrid(
                onSwitchToRulesTab: () => widget.onSwitchTab?.call(1),
              ),
              const SizedBox(height: 22),

              // ④ 数据与同步
              const SettingSectionTitle(title: '数据与同步'),
              SettingSection(
                children: [
                  SettingTile(
                    icon: Ionicons.storefrontOutline,
                    iconColor: AppColors.accentTeal,
                    title: '规则订阅市场',
                    subtitle: '探索并一键订阅最新聚合跨媒体解析源',
                    showArrow: true,
                    onTap: () => context.pushMarket(),
                  ),
                  SettingTile(
                    icon: Ionicons.cloudDownloadOutline,
                    iconColor: AppColors.accentBlue,
                    title: '离线下载',
                    subtitle: '管理已下载的小说与漫画，查看沙盒占用空间',
                    showArrow: true,
                    onTap: () => context.pushDownloads(),
                  ),
                  SettingTile(
                    icon: Ionicons.cloudOutline,
                    iconColor: AppColors.accentBlue,
                    title: '临时与网络缓存',
                    subtitle: _cacheSizeMB == null
                        ? '正在统计占用空间...'
                        : '当前占用 ${_cacheSizeMB!.toStringAsFixed(1)} MB',
                    trailing: _isCleaning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _cleanCacheOnly,
                            child: const Text(
                              '清理',
                              style: TextStyle(fontSize: 12, color: AppColors.primary),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 底部版本签名
              Center(
                child: Text(
                  'FluxForge v${appService.packageInfo?.version ?? "1.0.0"} · 极光微内核沙箱',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
