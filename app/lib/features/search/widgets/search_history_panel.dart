import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 搜索历史与探索推荐词面板
///
/// 未发起检索时的默认视图；顶部在无可用规则源时给出引导卡片。
/// 纯展示 + 回调上抛：历史记录的读写与跳转由宿主负责。
class SearchHistoryPanel extends StatelessWidget {
  const SearchHistoryPanel({
    super.key,
    required this.isDark,
    required this.hasActiveRules,
    required this.historyList,
    required this.hotSuggestions,
    required this.onPick,
    required this.onRemove,
    required this.onClearAll,
    required this.onGoMarket,
  });

  final bool isDark;

  /// 是否存在可用（已启用）的规则源；为 false 时展示引导导入卡片
  final bool hasActiveRules;

  final List<String> historyList;

  /// 推荐热门探测词
  final List<String> hotSuggestions;

  /// 选中某个历史词 / 推荐词
  final ValueChanged<String> onPick;

  /// 单项删除历史记录
  final ValueChanged<String> onRemove;

  /// 清空全部历史记录
  final VoidCallback onClearAll;

  /// 跳转规则市场导入源
  final VoidCallback onGoMarket;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 规则状态提示卡片 (若无可用规则则引导开启)
        if (!hasActiveRules) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '当前未启用任何解析规则，搜索将无法获取内容',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onGoMarket,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('去市场导入'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 搜索历史模块
        if (historyList.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '搜索历史',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                label: const Text('清空历史', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onClearAll,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: historyList.map((text) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onPick(text),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onRemove(text);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // 探索灵感推荐词
        Row(
          children: [
            const Icon(Ionicons.sparklesOutline, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              '探索推荐',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: hotSuggestions.map((text) {
            return ActionChip(
              label: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              backgroundColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 0.8,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onPressed: () => onPick(text),
            );
          }).toList(),
        ),
      ],
    );
  }
}
