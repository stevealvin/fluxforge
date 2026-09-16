import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../services/di.dart';
import '../../widgets/backup_sheet.dart';
import '../../widgets/setting_tile.dart';
import 'widgets/continue_watching_row.dart';
import 'widgets/profile_asset_grid.dart';
import 'widgets/profile_hero.dart';

/// 个人中心页面 (我的)
///
/// 经过重新设计，从「功能入口集合」升级为「个人资产仪表盘」，按五大语义区组织：
/// ① 身份 Hero（昵称 / 沙箱状态 / 主题三态 / 设置唯一入口）
/// ② 继续观看（跨媒体消费记录横滑流，一键续播）
/// ③ 我的资产（2×2 资产卡网格：收藏 / 历史 / 规则 / 足迹）
/// ④ 数据与同步（备份还原 / 规则市场 / 缓存治理）
/// ⑤ 系统与关于（偏好设置 / 沙箱日志 / 广告拦截 / 关于）
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

  /// 弹出「关于」信息面板（版本 / 构建号 / 平台 / 本地资产概览）
  Future<void> _showAboutSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final info = appService.packageInfo;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryLight, AppColors.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Ionicons.compassOutline, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FluxForge 流光视界',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '轻量级沙箱规则驱动的跨媒体聚合平台',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildAboutRow('版本号', 'v${info?.version ?? "1.0.0"}', isDark),
              _buildAboutRow('构建编号', info?.buildNumber ?? '1', isDark),
              _buildAboutRow('运行平台', defaultTargetPlatform.name, isDark),
              _buildAboutRow('规则引擎', 'QuickJS-NG 极光微内核沙箱', isDark),
              _buildAboutRow('本地规则', '${ruleService.rules.length} 条', isDark),
              _buildAboutRow('收藏条目', '${favoriteService.favorites.length} 部', isDark),
              _buildAboutRow('消费记录', '${playHistoryService.records.length} 条', isDark),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '本地自治 · 数据全量留存于设备',
                  style: TextStyle(
                    fontSize: 10.5,
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

  /// 「关于」面板的信息行
  Widget _buildAboutRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
        ],
      ),
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
                    icon: Ionicons.hardwareChipOutline,
                    iconColor: AppColors.accentPurple,
                    title: '数据备份与还原',
                    subtitle: '规则库、收藏、搜索历史与观看进度单文件 JSON 导出/导入',
                    showArrow: true,
                    onTap: () => showBackupSheet(context),
                  ),
                  SettingTile(
                    icon: Ionicons.storefrontOutline,
                    iconColor: AppColors.accentTeal,
                    title: '规则订阅市场',
                    subtitle: '探索并一键订阅最新聚合跨媒体解析源',
                    showArrow: true,
                    onTap: () => context.push('/market'),
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
              const SizedBox(height: 22),

              // ⑤ 系统与关于
              const SettingSectionTitle(title: '系统与关于'),
              SettingSection(
                children: [
                  SettingTile(
                    icon: Ionicons.optionsOutline,
                    iconColor: AppColors.primary,
                    title: '系统偏好设置',
                    subtitle: '播放手势、阅读排版、沙箱请求超时与广告拦截',
                    showArrow: true,
                    onTap: () => context.push('/settings'),
                  ),
                  // 沙箱日志（携带实时 ERROR 计数徽标）
                  ValueListenableBuilder<List<LogEntry>>(
                    valueListenable: AppLogger.logsNotifier,
                    builder: (context, logs, _) {
                      final errorCount = logs.where((l) => l.level == 'ERROR').length;
                      return SettingTile(
                        icon: Ionicons.documentTextOutline,
                        iconColor: AppColors.accentBlue,
                        title: '沙箱与系统日志',
                        subtitle: logs.isEmpty
                            ? '查看规则解析、console.log 与网络异常'
                            : '已记录 ${logs.length} 条日志',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (errorCount > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$errorCount ERROR',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                          ],
                        ),
                        onTap: () => context.push('/logs'),
                      );
                    },
                  ),
                  SettingTile(
                    icon: Ionicons.shieldCheckmarkOutline,
                    iconColor: AppColors.success,
                    title: '广告拦截规则',
                    subtitle: '管理内置浏览器的广告过滤规则与订阅源',
                    showArrow: true,
                    onTap: () => context.push('/adblock'),
                  ),
                  SettingTile(
                    icon: Ionicons.informationCircleOutline,
                    iconColor: AppColors.accentAmber,
                    title: '关于 FluxForge',
                    subtitle: '版本信息、运行底座与本地资产概览',
                    showArrow: true,
                    onTap: _showAboutSheet,
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
