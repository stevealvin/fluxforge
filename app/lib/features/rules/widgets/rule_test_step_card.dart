import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/rules/models/rule_test_step.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';

/// 单个测试阶段卡片
///
/// 按「状态徽章 → 摘要 → 核心指标 → 原始 JSON」四段渲染；
/// JSON 区默认折叠，展开由宿主通过 [onToggleExpanded] 回写 [RuleTestStep.isExpanded]。
class RuleTestStepCard extends StatelessWidget {
  const RuleTestStepCard({
    super.key,
    required this.step,
    required this.isDark,
    required this.onToggleExpanded,
  });

  final RuleTestStep step;
  final bool isDark;

  /// 展开 / 收起原始 JSON 预览区
  final VoidCallback onToggleExpanded;

  /// 状态颜色匹配
  static Color statusColorOf(RuleTestStepStatus status) {
    switch (status) {
      case RuleTestStepStatus.running:
        return AppColors.primary;
      case RuleTestStepStatus.success:
        return const Color(0xFF10B981); // Emerald
      case RuleTestStepStatus.failed:
        return Colors.redAccent;
      case RuleTestStepStatus.skipped:
        return Colors.orangeAccent;
      case RuleTestStepStatus.idle:
        return Colors.grey;
    }
  }

  /// 状态图标匹配
  static Widget statusIconOf(RuleTestStepStatus status) {
    switch (status) {
      case RuleTestStepStatus.running:
        return const LoadingIndicator.compact(size: 14, strokeWidth: 2);
      case RuleTestStepStatus.success:
        return const Icon(Icons.check_rounded, size: 16, color: Color(0xFF10B981));
      case RuleTestStepStatus.failed:
        return const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent);
      case RuleTestStepStatus.skipped:
        return const Icon(Icons.skip_next_rounded, size: 16, color: Colors.orangeAccent);
      case RuleTestStepStatus.idle:
        return const Icon(Icons.circle_outlined, size: 14, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = statusColorOf(step.status);
    final statusIcon = statusIconOf(step.status);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：阶段标题 + 状态徽章 + 耗时
          Row(
            children: [
              // 状态图标
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(child: statusIcon),
              ),
              const SizedBox(width: 10),

              // 标题与副标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // 耗时 Badge
              if (step.elapsedMs > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${step.elapsedMs}ms',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
            ],
          ),

          // 摘要信息 (Summary)
          if (step.summary != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.18), width: 0.8),
              ),
              child: Text(
                step.summary!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: isDark ? statusColor.withValues(alpha: 0.9) : statusColor,
                ),
              ),
            ),
          ],

          // 核心提取指标键值对 (Key Fields)
          if (step.keyFields.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg.withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: step.keyFields.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            entry.value,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // 展开/收起原始 JSON 按钮
          if (step.rawResponse != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onToggleExpanded,
                  icon: Icon(
                    step.isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                  ),
                  label: Text(
                    step.isExpanded ? '收起原始 JSON' : '查看原始 JSON',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                ),
                if (step.formattedJson != null)
                  IconButton(
                    icon: const Icon(Ionicons.copyOutline, size: 13),
                    tooltip: '复制该阶段 JSON',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: step.formattedJson!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制该阶段 JSON 数据'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
              ],
            ),
          ],

          // 折叠的原始 JSON 预览区
          if (step.isExpanded && step.formattedJson != null) ...[
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 220),
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  step.formattedJson!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF38BDF8), // 浅蓝代码高亮
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
