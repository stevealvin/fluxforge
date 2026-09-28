import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/utils/app_utils.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 「我的」页个人资产卡片网格 (ProfileAssetGrid)
///
/// 每张卡同时承载图标语义、主数值、标签与动态副信息（如「3 部有新更新」），
/// 各自独立监听对应服务，避免深层嵌套 ValueListenableBuilder。
///
/// **收藏卡已移除**：收藏入口迁到首页顶栏（发现页 AppBar），
/// 「有新更新」的信号也随之带到那个入口上 —— 同一份数据不设两个入口。
///
/// **规则卡已移除**：规则本就是底部导航的一级 Tab，资产卡只是同一入口的
/// 第二个门（还要靠下标回调跳转）—— 底部栏就在这一页正下方，走那一条更直接。
class ProfileAssetGrid extends StatelessWidget {
  const ProfileAssetGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _PlayHistoryAssetCard()),
        SizedBox(width: 10),
        Expanded(child: _DownloadAssetCard()),
      ],
    );
  }
}

/// 观看/阅读历史资产卡
class _PlayHistoryAssetCard extends StatelessWidget {
  const _PlayHistoryAssetCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PlayRecord>>(
      valueListenable: playHistoryService.recordsNotifier,
      builder: (context, records, _) {
        final latest = records.isNotEmpty ? records.first : null;
        return _AssetTile(
          icon: Ionicons.timeOutline,
          iconColor: AppColors.accentBlue,
          value: '${records.length} 条',
          label: '观看历史',
          subtitle: latest == null
              ? '暂无消费记录'
              : AppUtils.formatRelativeTime(latest.updatedAt),
          onTap: () => context.pushHistory(),
        );
      },
    );
  }
}

/// 离线下载管理资产卡
///
/// 取代原先的「搜索足迹」卡：搜索足迹已完整收纳在历史中心页内，
/// 在此重复出现只会造成同一份数据两个入口；而离线下载是「我的」页缺失的资产维度，
/// 且能给出任务数与进行中 / 失败状态这类一眼可读的信息。
class _DownloadAssetCard extends StatelessWidget {
  const _DownloadAssetCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DownloadTask>>(
      valueListenable: downloadService.tasksNotifier,
      builder: (context, tasks, _) {
        final runningCount = tasks
            .where(
              (t) =>
                  t.status == DownloadStatus.running ||
                  t.status == DownloadStatus.pending,
            )
            .length;
        final failedCount = tasks
            .where((t) => t.status == DownloadStatus.failed)
            .length;

        final String subtitle;
        if (tasks.isEmpty) {
          subtitle = '暂无离线内容';
        } else if (runningCount > 0) {
          subtitle = '正在下载 $runningCount 部';
        } else if (failedCount > 0) {
          subtitle = '$failedCount 部存在失败项';
        } else {
          subtitle = '全部下载完成';
        }

        return _AssetTile(
          icon: Ionicons.cloudDownloadOutline,
          iconColor: AppColors.accentAmber,
          value: '${tasks.length} 部',
          label: '下载管理',
          subtitle: subtitle,
          // 仅在存在失败项时亮红点：进行中属于正常状态，无需额外提示
          showBadge: failedCount > 0,
          onTap: () => context.pushDownloads(),
        );
      },
    );
  }
}

/// 通用资产卡片原子组件（图标徽章 + 主数值 + 标签 + 动态副信息）
class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.subtitle,
    this.showBadge = false,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String subtitle;
  final bool showBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                      ),
                    ),
                    if (showBadge) ...[
                      const SizedBox(width: 5),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
