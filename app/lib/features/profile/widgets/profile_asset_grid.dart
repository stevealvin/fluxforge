import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/utils/app_utils.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 「我的」页个人资产卡片网格 (ProfileAssetGrid)
///
/// 以 2×2 立式资产卡替代旧版「横排四个纯数字」的指标条：
/// 每张卡同时承载图标语义、主数值、标签与动态副信息（如「3 部有新更新」），
/// 各自独立监听对应服务，避免深层嵌套 ValueListenableBuilder。
class ProfileAssetGrid extends StatelessWidget {
  const ProfileAssetGrid({super.key, this.onSwitchToRulesTab});

  /// 切换到底部导航「规则」Tab 的回调（规则统计卡点击直达）
  final VoidCallback? onSwitchToRulesTab;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: _FavoriteAssetCard()),
            const SizedBox(width: 10),
            const Expanded(child: _PlayHistoryAssetCard()),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _RuleAssetCard(onTap: onSwitchToRulesTab)),
            const SizedBox(width: 10),
            const Expanded(child: _SearchHistoryAssetCard()),
          ],
        ),
      ],
    );
  }
}

/// 1. 追更收藏资产卡
class _FavoriteAssetCard extends StatelessWidget {
  const _FavoriteAssetCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<FavoriteItem>>(
      valueListenable: favoriteService.favoritesNotifier,
      builder: (context, favorites, _) {
        final updateCount = favorites.where((f) => f.hasUpdate).length;
        return _AssetTile(
          icon: Ionicons.bookmarkOutline,
          iconColor: AppColors.primary,
          value: '${favorites.length} 部',
          label: '追更收藏',
          subtitle: updateCount > 0 ? '$updateCount 部有新更新' : '暂无新更新',
          showBadge: updateCount > 0,
          onTap: () => context.pushFavorites(),
        );
      },
    );
  }
}

/// 2. 观看/阅读历史资产卡
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

/// 3. 我的规则资产卡（点击直达规则 Tab）
class _RuleAssetCard extends StatelessWidget {
  const _RuleAssetCard({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Rule>>(
      valueListenable: ruleService.rulesNotifier,
      builder: (context, rules, _) {
        return ValueListenableBuilder<Map<String, int>>(
          valueListenable: ruleService.latenciesNotifier,
          builder: (context, latencies, _) {
            final enabledCount = rules.where((r) => r.enabled).length;
            final failedCount =
                latencies.values.where((ms) => ms < 0 || ms > 2500).length;

            final String subtitle;
            if (latencies.isEmpty) {
              subtitle = '尚未连通测速';
            } else if (failedCount > 0) {
              subtitle = '$failedCount 条失效待治理';
            } else {
              subtitle = '连通性良好';
            }

            return _AssetTile(
              icon: Ionicons.codeSlashOutline,
              iconColor: AppColors.accentPurple,
              value: '$enabledCount/${rules.length}',
              label: '我的规则',
              subtitle: subtitle,
              showBadge: failedCount > 0,
              onTap: onTap,
            );
          },
        );
      },
    );
  }
}

/// 4. 搜索足迹资产卡
class _SearchHistoryAssetCard extends StatelessWidget {
  const _SearchHistoryAssetCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: historyService.searchHistoryNotifier,
      builder: (context, keywords, _) {
        return _AssetTile(
          icon: Ionicons.searchOutline,
          iconColor: AppColors.accentAmber,
          value: '${keywords.length} 条',
          label: '搜索足迹',
          subtitle: keywords.isEmpty ? '暂无搜索记录' : keywords.first,
          onTap: () => context.pushHistory(),
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
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
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
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
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
