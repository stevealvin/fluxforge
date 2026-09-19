import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';

/// 搜索结果底部状态组件（加载中菊花 / 无更多数据通栏提示）
///
/// 全局并发检索未结束时强调「仍在流式检索其余规则源」，仅上滑分页时才是普通「加载更多」。
class SearchResultFooter extends StatelessWidget {
  const SearchResultFooter({
    super.key,
    required this.isDark,
    required this.isLoading,
    this.loadingLabel = '加载更多中...',
  });

  final bool isDark;
  final bool isLoading;

  /// 加载态文案
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LoadingIndicator.compact(size: 14, strokeWidth: 1.8),
              const SizedBox(width: 8),
              Text(
                loadingLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          '— 已加载全部搜索结果 —',
          style: TextStyle(
            fontSize: 12,
            color: isDark
                ? AppColors.darkTextMuted.withValues(alpha: 0.7)
                : AppColors.lightTextMuted.withValues(alpha: 0.7),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
