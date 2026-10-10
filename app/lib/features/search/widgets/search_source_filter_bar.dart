import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/engines/search_aggregator.dart';
import 'package:fluxforge/features/search/models/rule_search_status.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';

/// 检索范围控制栏：来源过滤胶囊 + 行尾固定的筛选入口 + 状态提示与视图切换条
///
/// ### 两种形态（同一行，按是否已有结果切换）
/// - **搜索前**（[statuses] 为空）：左侧显示当前检索范围（如「仅搜索「影视」类型」），
///   右侧筛选入口可用 —— 「只搜影视」这类需求必须在**发起检索前**表达，
///   搜完再过滤已经晚了，所以这一行必须在搜索前就可达；
/// - **搜索后**：左侧换成各来源的胶囊（带命中数 / 检索中 / 异常态），
///   用于在已聚合的结果里切换查看哪个源。
///
/// 筛选入口固定在行尾、**不随胶囊横向滚动**，[hasKindFilter] 为真时以主色高亮
/// 提示「有筛选生效」。纯展示 + 回调上抛，状态由宿主持有。
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
    required this.onOpenFilter,
    required this.hasKindFilter,
    required this.kindLabel,
  });

  final bool isDark;

  /// 本轮参与检索的各源状态（顺序即胶囊顺序）；**为空表示还没发起检索**
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

  /// 点击行尾筛选按钮（弹出类型筛选面板）
  final VoidCallback onOpenFilter;

  /// 是否有「搜索前」的筛选条件生效（决定筛选按钮是否高亮）
  final bool hasKindFilter;

  /// 当前选中的类型名（搜索前那行提示用它）
  final String kindLabel;

  @override
  Widget build(BuildContext context) {
    final hasResults = statuses.isNotEmpty;
    final activeSearchingCount = statuses.where((s) => s.isSearching).length;

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
          Row(
            children: [
              // 左区右侧留出筛选按钮的位置，让按钮保持固定
              Expanded(
                child: hasResults
                    ? _buildSourceChips()
                    : _buildScopeHint(),
              ),

              // 筛选入口：固定在行尾，不随胶囊滚动
              _buildFilterButton(),
            ],
          ),

          // 状态提示与视图切换条：只在已有结果时出现
          //（搜索前显示「已汇聚 0 条」没有意义）
          if (hasResults) _buildStatusRow(activeSearchingCount),
        ],
      ),
    );
  }

  /// 搜索前：显示当前检索范围，让用户知道「这一搜会搜哪些源」
  Widget _buildScopeHint() {
    final textMuted = isDark
        ? AppColors.darkTextMuted
        : AppColors.lightTextMuted;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 4, 11),
      child: Row(
        children: [
          Icon(Ionicons.funnelOutline, size: 12, color: textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              hasKindFilter ? '仅搜索「$kindLabel」类型的规则源' : '搜索全部类型的规则源',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: hasKindFilter ? FontWeight.w600 : FontWeight.normal,
                color: hasKindFilter ? AppColors.primary : textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索后：各来源的过滤胶囊
  Widget _buildSourceChips() {
    final activeSearchingCount = statuses.where((s) => s.isSearching).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
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
              fontWeight: selectedRule == null
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: selectedRule == null
                  ? AppColors.primary
                  : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
            ),
            side: BorderSide(
              color: selectedRule == null
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 8),

          // 各规则单独胶囊
          ...statuses.map((status) {
            final isSelected = SearchAggregator.isSameRule(
              selectedRule,
              status.rule,
            );
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
                    ? const Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: Colors.orangeAccent,
                      )
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
                      : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary),
                ),
                side: BorderSide(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusRow(int activeSearchingCount) {
    return Padding(
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
                  Icon(
                    isGridView ? Ionicons.listOutline : Ionicons.gridOutline,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isGridView ? '列表排版' : '双列网格',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 行尾筛选按钮：有类型筛选生效时以主色高亮，否则是克制的浅底图标
  Widget _buildFilterButton() {
    final inactiveFg = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 10),
      child: Semantics(
        button: true,
        label: hasKindFilter ? '筛选（已生效）' : '筛选',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpenFilter,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: hasKindFilter
                  ? AppColors.primary
                  : (isDark ? AppColors.darkCard : AppColors.lightSurfaceVariant),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasKindFilter
                    ? AppColors.primary
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                width: 0.8,
              ),
            ),
            child: Icon(
              Ionicons.optionsOutline,
              size: 15,
              color: hasKindFilter ? Colors.white : inactiveFg,
            ),
          ),
        ),
      ),
    );
  }
}
