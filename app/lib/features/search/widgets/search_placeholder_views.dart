import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/engines/search_aggregator.dart';
import 'package:fluxforge/features/search/models/rule_search_status.dart';
import 'package:fluxforge/shared/widgets/app_empty_state.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';

/// 检索进行中但尚无源返回数据时的等待态
///
/// 展示受控并发池的调度进度（已完成 / 总数）与一键停止入口。
class SearchPendingView extends StatelessWidget {
  const SearchPendingView({
    super.key,
    required this.isDark,
    required this.statusMap,
    required this.onCancel,
  });

  final bool isDark;
  final Map<String, RuleSearchStatus> statusMap;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final total = statusMap.length;
    final finished = total - SearchAggregator.searchingCount(statusMap);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const LoadingIndicator.compact(size: 28, strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text(
              '全网流式聚合检索中...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              total > 0
                  ? '已调度 $total 个规则沙箱 (已完成 $finished 源)'
                  : '正在调度规则沙箱...',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: const Text('停止检索', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                side: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// 检索完成但无匹配结果的空态
///
/// 单源模式且该源异常时，额外给出「调试此规则」直达出口，
/// 把「搜不到」从死路变成可排查的起点。
class SearchEmptyView extends StatelessWidget {
  const SearchEmptyView({
    super.key,
    required this.isDark,
    required this.targetRule,
    required this.statusMap,
    required this.onRetry,
    required this.onGoMarket,
    required this.onDebugRule,
  });

  final bool isDark;
  final Rule? targetRule;
  final Map<String, RuleSearchStatus> statusMap;
  final VoidCallback onRetry;
  final VoidCallback onGoMarket;
  final ValueChanged<Rule> onDebugRule;

  @override
  Widget build(BuildContext context) {
    final targetStatus =
        targetRule != null ? statusMap[SearchAggregator.ruleKeyOf(targetRule)] : null;

    if (targetStatus != null && targetStatus.hasError) {
      final errorMessage = targetStatus.errorMessage;
      return Center(
        child: EmptyState(
          icon: Icons.error_outline_rounded,
          title: '规则「${targetRule!.name}」检索异常',
          description: errorMessage != null && errorMessage.isNotEmpty
              ? '错误原因: $errorMessage'
              : '目标源站点可能网络受阻或沙箱脚本解析错误，建议前往调试器查看',
          actionText: '调试此规则',
          onAction: () => onDebugRule(targetRule!),
        ),
      );
    }

    return Center(
      child: EmptyState(
        icon: Ionicons.searchOutline,
        title: '未检索到相关内容',
        description: targetRule != null
            ? '在「${targetRule!.name}」中未搜到结果，建议更换简短词汇'
            : '建议更换简短词汇，或前往规则中心开启更多源进行聚合检索',
        actionText: targetRule != null ? '重试搜索' : '去规则市场发现',
        onAction: targetRule != null ? onRetry : onGoMarket,
      ),
    );
  }
}
