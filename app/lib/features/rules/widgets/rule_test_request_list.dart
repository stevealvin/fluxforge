import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/sandbox/http_request_record.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 「网络」页：本轮测试期间的原生 HTTP 请求明细
///
/// 这些记录由 `RuleEngine` 经 `httpObserver` 抛出（见 `core/sandbox/http_request_record.dart`），
/// 生产运行时不会产生。展示重点是**每条请求真的打到了哪里、代价多少**：
/// 方法 + 路径 + 状态码 + 耗时 + 响应大小 + 重定向次数。
///
/// 之所以把「重定向」单独标出来：规则调试里最常见的一类误判就是
/// 「以为请求的是 A，实际被跳到了 B」，不显式标出就完全看不见。
class RuleTestRequestList extends StatelessWidget {
  const RuleTestRequestList({
    super.key,
    required this.isDark,
    required this.records,
  });

  final bool isDark;
  final List<HttpRequestRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_tethering_off_rounded,
                size: 34,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
              const SizedBox(height: 10),
              Text(
                '尚未捕获到网络请求',
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
                '执行一轮测试后，规则发起的每次 HTTP 请求都会列在这里',
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: records.length,
      itemBuilder: (context, index) => _buildTile(context, records[index], index),
    );
  }

  Widget _buildTile(BuildContext context, HttpRequestRecord record, int index) {
    final okColor = const Color(0xFF10B981);
    final statusColor = record.isOk ? okColor : Colors.redAccent;
    final mono = TextStyle(
      fontSize: 11,
      fontFamily: 'monospace',
      height: 1.4,
      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
    );

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      borderRadius: 13,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：序号 + 方法 + 路径 + 状态码
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  record.method,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  record.displayPath,
                  style: mono,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                record.error != null ? '失败' : '${record.statusCode}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 第二行：耗时 / 大小 / 重定向
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _metric(Icons.timer_outlined, '${record.elapsedMs}ms', isDark),
              if (record.sizeLabel.isNotEmpty)
                _metric(Icons.data_object_rounded, record.sizeLabel, isDark),
              if (record.hasRedirect)
                _metric(
                  Icons.call_split_rounded,
                  '重定向 ${record.redirectCount} 次',
                  isDark,
                  highlight: true,
                ),
            ],
          ),

          // 重定向后的最终地址：与原始地址不同才显示，避免噪音
          if (record.hasRedirect && record.finalUrl != record.url) ...[
            const SizedBox(height: 7),
            _subLine(
              '最终地址',
              record.finalUrl,
              isDark,
              color: const Color(0xFFF59E0B),
            ),
          ],

          // 失败原因
          if (record.error != null) ...[
            const SizedBox(height: 7),
            _subLine('失败原因', record.error!, isDark,
                color: Colors.redAccent),
          ],
        ],
      ),
    );
  }

  Widget _metric(IconData icon, String text, bool isDark,
      {bool highlight = false}) {
    final color = highlight
        ? const Color(0xFFF59E0B)
        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(fontSize: 10.5, color: color),
        ),
      ],
    );
  }

  Widget _subLine(String label, String value, bool isDark, {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          ),
        ),
        Expanded(
          child: GestureDetector(
            // 长按复制：完整 URL / 报错原文常要拿去别处核对
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: value));
              HapticFeedback.lightImpact();
            },
            child: Text(
              value,
              style: TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                height: 1.4,
                color: color ??
                    (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
