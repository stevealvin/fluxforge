import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/utils/app_utils.dart';
import 'package:fluxforge/core/utils/media_utils.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/shared/widgets/app_confirm_dialog.dart';
import 'package:fluxforge/shared/widgets/app_delete_snack_bar.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';

/// 打开消费记录对应的媒体详情页
///
/// 抽为顶层函数，供「历史中心」与「我的」页继续观看横滑流共同复用，
/// 避免两处重复维护同一套跳转与规则匹配逻辑。
void openPlayRecord(BuildContext context, PlayRecord record) {
  HapticFeedback.lightImpact();

  final matchedRule = matchRuleForRecord(record);

  // 有有效网络地址时走规则详情页（可自动解析详情并完成断点续播）
  if (record.url.isNotEmpty) {
    context.pushRuleDetail(
      RuleDetailArgs(
        rule: matchedRule,
        title: record.title,
        url: record.url,
        cover: record.cover,
      ),
    );
    return;
  }

  // 兜底：无有效地址时走通用详情分发（同样带上规则，别让详情页去猜）
  context.pushMediaDetail(
    MediaDetailArgs(
      type: record.mediaType,
      title: record.title,
      url: record.url,
      cover: record.cover,
      rule: matchedRule,
    ),
  );
}

/// 消费记录 → 规则：先按 `ruleId` 精确匹配，匹配不到再按 URL host 反查
///
/// **为什么要做 host 兜底**：记录里的 `ruleId` 可能为空（早期数据、或规则被删后重建），
/// 这时若只传 null，详情页会依次退化到「按 host 反查」→「`rules.first` 随便挑一条」，
/// 后者会让 baseUrl 彻底错位。这里提前用与详情页同源的判据匹配好，把结果传下去。
Rule? matchRuleForRecord(PlayRecord record) {
  for (final rule in ruleService.rules) {
    if (record.ruleId.isNotEmpty && rule.id?.toString() == record.ruleId) {
      return rule;
    }
  }

  // 兜底：直接用 baseUrl 反查（判据统一在 Rule.matchesUrl）
  return ruleService.matchByUrl(record.id);
}

/// 历史管理中心页面 (HistoryCenterPage)
///
/// 统一收纳「观看/阅读历史（含断点续播进度）」与「搜索足迹」两大维度：
/// - 支持按媒体类型（影视 / 小说 / 漫画）横向过滤；
/// - 单条删除与一键清空（带二次确认）；
/// - 点击历史条目直达详情页，由详情页自动完成断点续播。
class HistoryCenterPage extends StatefulWidget {
  const HistoryCenterPage({super.key});

  @override
  State<HistoryCenterPage> createState() => _HistoryCenterPageState();
}

class _HistoryCenterPageState extends State<HistoryCenterPage> {
  /// 当前媒体类型过滤 ('all' | 'video' | 'novel' | 'comic')
  String _selectedFilter = 'all';

  /// 清空全部历史（二次确认后同时清空消费历史与搜索足迹）
  Future<void> _confirmClearAll() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '清空全部历史',
      message: '将同时清空「观看/阅读历史」与「搜索足迹」，该操作不可撤销。',
      confirmText: '确认清空',
    );
    if (!confirmed) return;

    await playHistoryService.clear();
    await historyService.clearHistory();
    if (!mounted) return;
    showDeleteSnackBar(context, message: '已清空全部历史记录');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text(
          '历史中心',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: '清空全部历史',
            icon: const Icon(Ionicons.trashOutline, size: 20),
            onPressed: _confirmClearAll,
          ),
        ],
      ),
      body: ValueListenableBuilder<List<PlayRecord>>(
        valueListenable: playHistoryService.recordsNotifier,
        builder: (context, records, _) {
          return ValueListenableBuilder<List<String>>(
            valueListenable: historyService.searchHistoryNotifier,
            builder: (context, keywords, _) {
              final filtered = _selectedFilter == 'all'
                  ? records
                  : records
                        .where((r) => r.mediaType == _selectedFilter)
                        .toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // 1. 观看与阅读历史
                  _buildSectionHeader(
                    isDark: isDark,
                    title: '观看与阅读历史',
                    count: records.length,
                  ),
                  const SizedBox(height: 10),
                  _buildFilterBar(isDark),
                  const SizedBox(height: 10),
                  if (filtered.isEmpty)
                    _buildEmptyHint(
                      isDark: isDark,
                      icon: Ionicons.timeOutline,
                      text: records.isEmpty
                          ? '暂无观看或阅读记录，去发现页开启第一段旅程'
                          : '当前筛选类型下暂无记录',
                    )
                  else
                    ...filtered.map(
                      (record) => _buildRecordCard(record, isDark),
                    ),

                  const SizedBox(height: 24),

                  // 2. 搜索足迹
                  _buildSectionHeader(
                    isDark: isDark,
                    title: '搜索足迹',
                    count: keywords.length,
                  ),
                  const SizedBox(height: 10),
                  if (keywords.isEmpty)
                    _buildEmptyHint(
                      isDark: isDark,
                      icon: Ionicons.searchOutline,
                      text: '暂无搜索足迹',
                    )
                  else
                    _buildSearchChips(keywords, isDark),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// 分组标题 + 计数徽标
  Widget _buildSectionHeader({
    required bool isDark,
    required String title,
    required int count,
  }) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),
      ],
    );
  }

  /// 媒体类型过滤条
  Widget _buildFilterBar(bool isDark) {
    const filters = <List<String>>[
      ['all', '全部'],
      ['video', '影视'],
      ['novel', '小说'],
      ['comic', '漫画'],
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f[0];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f[1]),
              selected: isSelected,
              selectedColor: AppColors.primary,
              backgroundColor: isDark
                  ? AppColors.darkCard
                  : AppColors.lightSurface,
              labelStyle: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary),
              ),
              side: BorderSide(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                width: 0.8,
              ),
              onSelected: (val) {
                if (val) setState(() => _selectedFilter = f[0]);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 单条消费记录卡片（封面 + 类型 + 进度 + 相对时间 + 删除）
  Widget _buildRecordCard(PlayRecord record, bool isDark) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      borderRadius: 14,
      onTap: () => openPlayRecord(context, record),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 74,
              child: AppImage(imageUrl: record.cover, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),

          // 主体信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // 类型徽标
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            MediaDisplay.typeIcon(record.mediaType),
                            size: 10,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            MediaDisplay.typeLabel(record.mediaType),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        record.progressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 续播进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: record.progress,
                    minHeight: 3,
                    backgroundColor: isDark ? Colors.white12 : Colors.black12,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppUtils.formatRelativeTime(record.updatedAt),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),

          // 删除单条
          IconButton(
            tooltip: '删除该条记录',
            icon: const Icon(
              Ionicons.closeCircleOutline,
              size: 16,
              color: Colors.grey,
            ),
            onPressed: () => playHistoryService.remove(record.id),
          ),
        ],
      ),
    );
  }

  /// 搜索足迹标签流
  Widget _buildSearchChips(List<String> keywords, bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keywords.map((keyword) {
        return InputChip(
          label: Text(keyword, style: const TextStyle(fontSize: 12)),
          backgroundColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
          side: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.8,
          ),
          deleteIcon: const Icon(Ionicons.closeOutline, size: 14),
          onDeleted: () => historyService.removeHistory(keyword),
          onPressed: () {
            HapticFeedback.selectionClick();
            context.pushSearch(keyword: keyword);
          },
        );
      }).toList(),
    );
  }

  /// 轻量空态提示（避免整页大空态造成视觉空洞）
  Widget _buildEmptyHint({
    required bool isDark,
    required IconData icon,
    required String text,
  }) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      borderRadius: 14,
      color: isDark ? AppColors.darkCard : AppColors.lightCard,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 16,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
