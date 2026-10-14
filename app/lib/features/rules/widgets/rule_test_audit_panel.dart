import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/rules/models/rule_data_audit.dart';
import 'package:fluxforge/features/rules/models/rule_test_step.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 「体检」页：全量字段覆盖 + 契约检查
///
/// 补上一个长期缺口 —— 规则测试此前只检查**首项**字段（title/url/cover），
/// 于是「20 条里有 3 条缺封面」「链接是相对路径」这类问题在页面上完全看不出来，
/// 要等用户点进去才会暴露。
///
/// 呈现按阶段分组；每阶段先看**字段覆盖**（数据全不全），再看**契约检查**
/// （规则符不符合规范）—— 两者混在一起会让人分不清该改规则还是改站点适配。
class RuleTestAuditPanel extends StatelessWidget {
  const RuleTestAuditPanel({
    super.key,
    required this.isDark,
    required this.steps,
  });

  final bool isDark;
  final List<RuleTestStep> steps;

  /// 字段名 → 中文标签
  static const Map<String, String> _fieldLabels = {
    'title': '标题',
    'url': '链接',
    'cover': '封面',
    'desc': '描述',
  };

  @override
  Widget build(BuildContext context) {
    final audited = steps
        .where((s) => s.coverages.isNotEmpty || s.checks.isNotEmpty)
        .toList();

    if (audited.isEmpty) return _buildEmptyState();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _buildSummary(audited),
        const SizedBox(height: 12),
        for (final step in audited) _buildStageBlock(step),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Ionicons.medkitOutline,
              size: 34,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              '暂无可体检的数据',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '发现 / 搜索 / 详情阶段返回条目后，这里会统计各字段的覆盖情况',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部小结：把「几个通过 / 几个警告」先给出来，不必自己数
  Widget _buildSummary(List<RuleTestStep> audited) {
    final levels = [
      ...audited.expand((s) => s.coverages.map((c) => c.level)),
      ...audited.expand((s) => s.checks.map((c) => c.level)),
    ];
    final okCount = levels.where((l) => l == AuditLevel.ok).length;
    final warnCount = levels.where((l) => l == AuditLevel.warn).length;
    final failCount = levels.where((l) => l == AuditLevel.fail).length;
    final worst = auditWorstOf(levels);
    final accent = _colorOf(worst);

    return AppCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Row(
        children: [
          Icon(_iconOf(worst), size: 16, color: accent),
          const SizedBox(width: 8),
          Text(
            worst == AuditLevel.ok ? '数据体检通过' : '数据体检发现异常',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const Spacer(),
          Text(
            [
              if (okCount > 0) '✅ $okCount',
              if (warnCount > 0) '⚠️ $warnCount',
              if (failCount > 0) '❌ $failCount',
            ].join('  '),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageBlock(RuleTestStep step) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 阶段标题
          Row(
            children: [
              Text(
                step.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              if (step.hasAuditIssue) ...[
                const SizedBox(width: 6),
                Icon(
                  _iconOf(step.auditLevel),
                  size: 13,
                  color: _colorOf(step.auditLevel),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),

          // 字段覆盖：每个字段一枚 pill，一行扫完
          if (step.coverages.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: step.coverages
                  .map((c) => _buildCoveragePill(c))
                  .toList(),
            ),

          // 契约检查
          if (step.checks.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final check in step.checks) _buildCheckRow(check),
          ],
        ],
      ),
    );
  }

  Widget _buildCoveragePill(FieldCoverage coverage) {
    final color = _colorOf(coverage.level);
    final label = _fieldLabels[coverage.field] ?? coverage.field;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            coverage.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckRow(ContractCheck check) {
    final color = _colorOf(check.level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconOf(check.level), size: 12, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.name,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  check.detail,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorOf(AuditLevel level) {
    switch (level) {
      case AuditLevel.ok:
        return const Color(0xFF10B981);
      case AuditLevel.warn:
        return const Color(0xFFF59E0B);
      case AuditLevel.fail:
        return Colors.redAccent;
    }
  }

  static IconData _iconOf(AuditLevel level) {
    switch (level) {
      case AuditLevel.ok:
        return Icons.check_circle_rounded;
      case AuditLevel.warn:
        return Icons.error_rounded;
      case AuditLevel.fail:
        return Icons.cancel_rounded;
    }
  }
}
