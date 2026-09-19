import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/features/rules/engines/rule_test_log_filter.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 底部实时沙箱控制台 (Console Logcat)
///
/// 展示与当前规则相关的沙箱日志；支持一键复制全部、长按复制单条、收起/展开。
/// 日志的筛选由 [RuleTestLogFilter] 完成，本组件只负责渲染与交互。
class RuleTestConsolePanel extends StatelessWidget {
  const RuleTestConsolePanel({
    super.key,
    required this.isDark,
    required this.logs,
    required this.expanded,
    required this.isTesting,
    required this.scrollController,
    required this.onToggleExpanded,
  });

  final bool isDark;

  /// 已按当前规则过滤后的日志列表
  final List<LogEntry> logs;

  final bool expanded;

  /// 测试进行中（空态文案区分「等待输出」与「尚未开始」）
  final bool isTesting;

  /// 由宿主持有，用于新日志到达时自动滚到底部
  final ScrollController scrollController;

  final VoidCallback onToggleExpanded;

  /// 控制台日志级别颜色
  static Color logLevelColor(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return Colors.redAccent;
      case 'WARN':
        return Colors.amberAccent;
      case 'DEBUG':
        return Colors.lightBlueAccent;
      case 'INFO':
      default:
        return const Color(0xFF34D399); // 浅翡翠绿
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 控制台头部操作区
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Ionicons.terminalOutline, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    '沙箱实时控制台 (Console)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${logs.length}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (logs.isNotEmpty)
                    IconButton(
                      icon: const Icon(Ionicons.copyOutline, size: 16),
                      tooltip: '复制全部控制台日志',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final logText = logs.map(RuleTestLogFilter.consoleLine).join('\n');
                        Clipboard.setData(ClipboardData(text: logText));
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已复制 ${logs.length} 条控制台日志'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  IconButton(
                    icon: Icon(
                      expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    tooltip: expanded ? '收起控制台' : '展开控制台',
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggleExpanded,
                  ),
                ],
              ),
            ],
          ),

          if (expanded) ...[
            const SizedBox(height: 8),
            Container(
              height: 180,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        isTesting ? '等待沙箱 console 输出...' : '暂无调试日志，点击上方“开始测试”启动',
                        style: const TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final logColor = logLevelColor(log.level);
                        final logText = RuleTestLogFilter.consoleLine(log);

                        return InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onLongPress: () {
                            Clipboard.setData(ClipboardData(text: logText));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已复制日志: ${log.message}'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                            child: SelectableText.rich(
                              TextSpan(
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.3),
                                children: [
                                  TextSpan(
                                    text: '[${log.level}] ',
                                    style: TextStyle(color: logColor, fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: log.message,
                                    style: const TextStyle(color: Color(0xFFE2E8F0)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
