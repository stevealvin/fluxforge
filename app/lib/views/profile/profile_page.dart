import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../models/rule.dart';
import '../../services/di.dart';
import '../../services/favorite_service.dart';
import '../../widgets/app_card.dart';

/// 个人中心页面 (我的)
/// 
/// 经过深度精简与现代化重构：
/// 剔除静态文本假弹窗、开发调试展廊与多重重复入口
/// 聚焦核心资产（我的追更、搜索足迹、数据备份、规则市场与系统偏好）
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  double _cacheSizeMB = 0.0;
  bool _isCleaning = false;

  @override
  void initState() {
    super.initState();
    _fetchCacheSize();
  }

  /// 计算临时缓存占用
  Future<void> _fetchCacheSize() async {
    final size = await appService.getCacheSizeInMB();
    if (mounted) {
      setState(() => _cacheSizeMB = size);
    }
  }

  /// 快速清理缓存
  Future<void> _quickCleanCache() async {
    if (_isCleaning) return;
    HapticFeedback.lightImpact();
    setState(() => _isCleaning = true);

    await appService.clearCache();
    await historyService.clearHistory();
    await _fetchCacheSize();

    if (mounted) {
      setState(() => _isCleaning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已成功释放本地临时缓存与搜索足迹')),
      );
    }
  }

  /// 弹出全量备份与还原弹窗
  void _showBackupSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  '数据全量备份与还原',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(LucideIcons.fileUp, color: AppColors.primary),
                title: const Text('一键导出备份数据包'),
                subtitle: const Text('将规则库、收藏与搜索历史打包为 JSON 并分享/保存至本地', style: TextStyle(fontSize: 11)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await backupService.exportBackup();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('导出备份失败: $e')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.fileDown, color: Colors.amber),
                title: const Text('从 JSON 文本/剪贴板恢复'),
                subtitle: const Text('解析备份文件，支持合并追加或全量覆盖', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImportRestoreDialog(context, isDark);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹出恢复导入输入框
  void _showImportRestoreDialog(BuildContext context, bool isDark) {
    final controller = TextEditingController();
    bool mergeMode = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('恢复备份数据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请粘贴导出的 FluxForge 备份 JSON 文本内容：',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 4,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: '{\n  "app": "FluxForge",\n  "data": { ... }\n}',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.clipboard, size: 16),
                    tooltip: '粘贴剪贴板',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        setDialogState(() {
                          controller.text = data!.text!;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: mergeMode,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      setDialogState(() {
                        mergeMode = val ?? true;
                      });
                    },
                  ),
                  GestureDetector(
                    onTap: () => setDialogState(() => mergeMode = !mergeMode),
                    child: Text(
                      mergeMode ? '合并导入 (保留现有，追加新增)' : '完全覆盖 (清空现有，以备份为准)',
                      style: TextStyle(
                        fontSize: 12,
                        color: mergeMode ? AppColors.primary : Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                final jsonStr = controller.text.trim();
                if (jsonStr.isEmpty) return;

                final result = await backupService.restoreBackup(
                  jsonStr: jsonStr,
                  merge: mergeMode,
                );

                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result.success
                            ? '${result.message}：规则+${result.rulesImported}，收藏+${result.favoritesImported}'
                            : result.message,
                      ),
                    ),
                  );
                }
              },
              child: const Text('执行恢复'),
            ),
          ],
        ),
      ),
    );
  }

  /// 查看运行日志弹窗
  void _showLogsDialog(BuildContext context) {
    final logs = AppLogger.getLogs();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('沙箱运行日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: logs.isEmpty
              ? const Center(child: Text('当前无报错记录，系统运行良好'))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${log.time.toIso8601String().substring(11, 19)} [${log.level}] ${log.message}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppLogger.clear();
              Navigator.pop(ctx);
            },
            child: const Text('清空日志'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
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
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. 顶部用户身份与状态卡片 (极光徽标 + 设备/离线沙箱状态 + 快捷设置/主题)
            _buildUserHeader(context, isDark),
            const SizedBox(height: 16),

            // 2. 核心资产指标看板 (追更收藏、搜索足迹、本地规则、临时缓存)
            _buildMetricsStrip(context, isDark),
            const SizedBox(height: 16),

            // 3. 正在追更状态卡片 (有更新高亮，点击直达)
            _buildRecentUpdateBanner(context, isDark),
            const SizedBox(height: 16),

            // 4. 核心功能菜单卡片 (收敛四大实用功能，无多余重复)
            _buildActionMenuCard(context, isDark),
            const SizedBox(height: 28),

            // 5. 极简底部版权与沙箱状态
            _buildFooter(context, isDark),
          ],
        ),
      ),
    );
  }

  /// 1. 顶部用户身份卡片
  Widget _buildUserHeader(BuildContext context, bool isDark) {
    return Row(
      children: [
        // 极光渐变品牌头像
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF059669)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(LucideIcons.compass, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(width: 14),

        // 用户/系统标识
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
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'QuickJS 规则沙箱就绪 · 纯本地驱动',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 主题切换按钮
        IconButton(
          tooltip: '快速切换深浅主题',
          icon: Icon(
            isDark ? LucideIcons.moon : LucideIcons.sun,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            size: 20,
          ),
          onPressed: () => appService.toggleThemeMode(currentIsDark: isDark),
        ),

        // 设置入口
        IconButton(
          tooltip: '系统偏好设置',
          icon: Icon(
            LucideIcons.settings,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            size: 20,
          ),
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  /// 2. 核心资产指标看板 (4 列数据)
  Widget _buildMetricsStrip(BuildContext context, bool isDark) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      borderRadius: 18,
      child: ValueListenableBuilder<List<FavoriteItem>>(
        valueListenable: favoriteService.favoritesNotifier,
        builder: (context, favorites, _) {
          return ValueListenableBuilder<List<Rule>>(
            valueListenable: ruleService.rulesNotifier,
            builder: (context, rules, _) {
              return ValueListenableBuilder<List<String>>(
                valueListenable: historyService.searchHistoryNotifier,
                builder: (context, history, _) {
                  return Row(
                    children: [
                      // 1. 追更收藏 (支持呼吸红点)
                      _buildMetricItem(
                        label: '追更收藏',
                        value: '${favorites.length} 部',
                        hasBadge: favoriteService.hasAnyUpdate,
                        isDark: isDark,
                        onTap: () => context.push('/favorites'),
                      ),
                      _buildMetricDivider(isDark),

                      // 2. 搜索足迹
                      _buildMetricItem(
                        label: '搜索足迹',
                        value: '${history.length} 条',
                        isDark: isDark,
                        onTap: () => context.push('/search'),
                      ),
                      _buildMetricDivider(isDark),

                      // 3. 本地规则
                      _buildMetricItem(
                        label: '已载规则',
                        value: '${rules.where((r) => r.enabled).length}/${rules.length}',
                        isDark: isDark,
                        onTap: () => context.push('/market'),
                      ),
                      _buildMetricDivider(isDark),

                      // 4. 临时缓存
                      _buildMetricItem(
                        label: '临时缓存',
                        value: _isCleaning ? '清理中...' : '${_cacheSizeMB.toStringAsFixed(1)}M',
                        isDark: isDark,
                        onTap: _quickCleanCache,
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    bool hasBadge = false,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasBadge)
                    Positioned(
                      top: -2,
                      right: -8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricDivider(bool isDark) {
    return Container(
      width: 1,
      height: 24,
      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
    );
  }

  /// 3. 正在追更状态微缩卡片
  Widget _buildRecentUpdateBanner(BuildContext context, bool isDark) {
    return ValueListenableBuilder<List<FavoriteItem>>(
      valueListenable: favoriteService.favoritesNotifier,
      builder: (context, favorites, _) {
        final hasUpdate = favorites.any((item) => item.hasUpdate);
        final updateItem = favorites.cast<FavoriteItem?>().firstWhere(
              (item) => item?.hasUpdate == true,
              orElse: () => favorites.isNotEmpty ? favorites.first : null,
            );

        return AppCard(
          borderRadius: 16,
          padding: const EdgeInsets.all(14),
          onTap: () => context.push('/favorites'),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: hasUpdate
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : (isDark ? Colors.white10 : Colors.black12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasUpdate ? LucideIcons.sparkles : LucideIcons.bookmarkCheck,
                  color: hasUpdate ? AppColors.primary : Colors.grey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasUpdate ? '发现新更新未看' : '追更追更状态',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: hasUpdate ? AppColors.primary : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      updateItem != null
                          ? (hasUpdate
                              ? '${updateItem.title} · ${updateItem.latestEpisode}'
                              : '《${updateItem.title}》已是最新进度')
                          : '暂无收藏，去发现心仪影视小说',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
            ],
          ),
        );
      },
    );
  }

  /// 4. 核心功能菜单卡片 (收敛四大实用模块)
  Widget _buildActionMenuCard(BuildContext context, bool isDark) {
    return AppCard(
      borderRadius: 18,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 1. 我的收藏与追更
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.bookmark, color: AppColors.primary, size: 18),
            ),
            title: const Text('我的收藏与追更', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('管理关注的剧集、小说与漫画更新', style: TextStyle(fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (favoriteService.hasAnyUpdate)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              ],
            ),
            onTap: () => context.push('/favorites'),
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),

          // 2. 本地全量数据备份与还原
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.hardDriveDownload, color: Colors.purpleAccent, size: 18),
            ),
            title: const Text('数据备份与还原', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('规则库、收藏夹及历史记录单文件 JSON 导出/导入', style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => _showBackupSheet(context, isDark),
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),

          // 3. 规则订阅市场
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.store, color: Colors.teal, size: 18),
            ),
            title: const Text('规则订阅市场', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('探索与一键订阅最新聚合跨媒体解析源', style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => context.push('/market'),
          ),
          Divider(height: 1, indent: 56, color: isDark ? AppColors.darkBorder : AppColors.lightBorder),

          // 4. 系统偏好设置
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.sliders, color: Colors.blueAccent, size: 18),
            ),
            title: const Text('系统偏好设置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text('播放手势、小说翻页、沙箱请求超时、广告拦截', style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  /// 5. 底部版权与诊断入口
  Widget _buildFooter(BuildContext context, bool isDark) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _showLogsDialog(context),
          child: Text(
            '查看沙箱运行诊断日志',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'FluxForge v${appService.packageInfo?.version ?? "1.0.0"} · 极光微内核沙箱',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),
      ],
    );
  }
}
