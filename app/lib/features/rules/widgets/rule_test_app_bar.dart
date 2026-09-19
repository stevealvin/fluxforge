import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';

/// 规则调试页顶部导航栏
///
/// 标题区展示「规则名 + 媒体类型徽章 + 源站地址」（长文本自动省略），
/// 动作区提供「复制诊断报告」与「清空控制台日志」两个出口。
class RuleTestAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RuleTestAppBar({
    super.key,
    required this.rule,
    required this.onBack,
    required this.onCopyReport,
    required this.onClearLogs,
  });

  final Rule rule;

  /// 返回上一级（导航策略由页面决定，组件不感知路由实现）
  final VoidCallback onBack;

  /// 复制完整 Markdown 调试诊断报告
  final VoidCallback onCopyReport;

  /// 清空沙箱控制台日志
  final VoidCallback onClearLogs;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      titleSpacing: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: onBack,
        tooltip: '返回',
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  '规则调试 · ${rule.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  rule.type.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            rule.baseUrl.isNotEmpty ? rule.baseUrl : '无源站地址',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Ionicons.copyOutline, size: 18),
          tooltip: '复制调试诊断报告',
          onPressed: onCopyReport,
        ),
        IconButton(
          icon: const Icon(Ionicons.trashOutline, size: 18),
          tooltip: '清空沙箱控制台日志',
          onPressed: onClearLogs,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
