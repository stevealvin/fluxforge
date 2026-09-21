import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/engines/search_aggregator.dart';
import 'package:fluxforge/features/search/models/rule_search_status.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';

/// 来源规则过滤横向滑动胶囊栏 + 状态提示与视图切换条
///
/// 仅在聚合多源检索且源数大于 1 时呈现（单源模式由宿主隐藏以保持界面清爽）。
/// 纯展示 + 回调上抛：选中源与视图模式的持久化由宿主持有。
class SearchSourceFilterBar extends StatelessWidget {
  const SearchSourceFilterBar({
    super.key,
    required this.isDark,
    required this.statuses,
    required this.totalCount,
    required this.displayCount,
    required this.selectedRule,
    required this.isLoading,
    required this.isGridView,
    required this.onRuleSelected,
    required this.onToggleView,
  });

  final bool isDark;

  /// 本轮参与检索的各源状态（顺序即胶囊顺序）
  final List<RuleSearchStatus> statuses;

  /// 全源聚合到的总条目数（「全部」胶囊计数）
  final int totalCount;

  /// 当前筛选后实际展示的条目数
  final int displayCount;

  /// 当前选中的源（null 代表「全部」）
  final Rule? selectedRule;

  final bool isLoading;

  /// true 为双列瀑布流海报网格，false 为紧凑卡片列表
  final bool isGridView;

  final ValueChanged<Rule?> onRuleSelected;

  final ValueChanged<bool> onToggleView;

  @override
  Widget build(BuildContext context) {
    final activeSearchingCount =
        statuses.where((s) => s.isSearching).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // “全部”源胶囊
                FilterChip(
                  label: Text('全部 ($totalCount)'),
                  selected: selectedRule == null,
                  onSelected: (selected) {
                    onRuleSelected(null);
                  },
                  showCheckmark: false,
                  avatar: activeSearchingCount > 0
                      ? const AppLoading.compact(size: 12, strokeWidth: 1.5)
                      : null,
                  selectedColor: AppColors.primary.withValues(alpha: 0.16),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: selectedRule == null ? FontWeight.bold : FontWeight.normal,
                    color: selectedRule == null
                        ? AppColors.primary
                        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                  side: BorderSide(
                    color: selectedRule == null
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                const SizedBox(width: 8),

                // 各规则单独胶囊
                ...statuses.map((status) {
                  final isSelected =
                      SearchAggregator.isSameRule(selectedRule, status.rule);
                  final ruleName = status.rule.name;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      onSelected: (selected) {
                        onRuleSelected(selected ? status.rule : null);
                      },
                      showCheckmark: false,
                      avatar: status.isSearching
                          ? const AppLoading.compact(size: 12, strokeWidth: 1.5)
                          : status.hasError
                              ? const Icon(Icons.error_outline_rounded,
                                  size: 14, color: Colors.orangeAccent)
                              : null,
                      label: Text(
                        status.hasError
                            ? '$ruleName (异常)'
                            : '$ruleName (${status.count})',
                      ),
                      selectedColor: AppColors.primary.withValues(alpha: 0.16),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.5)
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  );
                }),
              ],
            ),
          ),
          // 状态提示与视图切换条
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isLoading
                      ? '正在并发检索各源数据 (剩余 $activeSearchingCount 源)...'
                      : '已汇聚 $displayCount 条检索结果',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
                // 列表 / 双列网格视图切换按键
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onToggleView(!isGridView),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(isGridView ? Ionicons.listOutline : Ionicons.gridOutline,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isGridView ? '列表排版' : '双列网格',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary),
                        ),
                      ],
                    ),
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
