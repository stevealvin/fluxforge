import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/media/novel/reader/models/page_turn_mode.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 排版设置扩展面板（护眼底色 / 翻页模式 / 字号 / 行距）
///
/// 纯展示组件：所有参数与行为均通过属性上抛，组件本身不持有状态、
/// 也不接触偏好持久化 —— 「写偏好」由上层在回调里完成。
///
/// 注意：本组件返回的是 [Positioned]，需置于 `Stack` 内使用，
/// 定位常量（`bottom: 96` 等）与组件本身放在一起，避免上下层各自维护一份。
class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({
    super.key,
    required this.readerTheme,
    required this.fontSize,
    required this.lineHeight,
    required this.pageMode,
    required this.onThemeSelected,
    required this.onPageModeSelected,
    required this.onDecreaseFont,
    required this.onIncreaseFont,
    required this.onLineHeightChangeStart,
    required this.onLineHeightChanged,
    required this.onLineHeightChangeEnd,
  });

  final ReaderTheme readerTheme;
  final double fontSize;
  final double lineHeight;
  final PageTurnMode pageMode;

  /// 选择护眼底色
  final ValueChanged<ReaderTheme> onThemeSelected;

  /// 选择了与当前**不同**的翻页模式（点当前项不会触发）
  final ValueChanged<PageTurnMode> onPageModeSelected;

  /// 字号减一（边界判断由上层负责）
  final VoidCallback onDecreaseFont;

  /// 字号加一（边界判断由上层负责）
  final VoidCallback onIncreaseFont;

  /// 拖动行距前锚定阅读位置
  final VoidCallback onLineHeightChangeStart;

  /// 行距实时变化
  final ValueChanged<double> onLineHeightChanged;

  /// 松手后统一还原阅读位置（避免连续拖动时页面抖动）
  final VoidCallback onLineHeightChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 96,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: readerTheme.bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: readerTheme.subText.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 护眼底色选择器
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ReaderTheme.values.map((th) {
                final isSelected = th == readerTheme;
                return GestureDetector(
                  onTap: () => onThemeSelected(th),
                  child: Container(
                    width: 68,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: th.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : Colors.black12,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        th.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: th.text,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // 翻页模式选择（与底栏快捷切换共享同一套位置保持逻辑）
            Row(
              children: [
                Text('翻页', style: TextStyle(fontSize: 13, color: readerTheme.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: PageTurnMode.values.map((mode) {
                      final isSelected = mode == pageMode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(mode.label, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: readerTheme.bg,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : readerTheme.text,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : readerTheme.subText.withValues(alpha: 0.35),
                          ),
                          onSelected: (val) {
                            if (val && !isSelected) onPageModeSelected(mode);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 字号调节
            Row(
              children: [
                Text('字号', style: TextStyle(fontSize: 13, color: readerTheme.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(40, 32),
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: readerTheme.subText.withValues(alpha: 0.4)),
                        ),
                        onPressed: onDecreaseFont,
                        child: Text('A-', style: TextStyle(color: readerTheme.text)),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${fontSize.round()} px',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: readerTheme.text,
                            ),
                          ),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(40, 32),
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: readerTheme.subText.withValues(alpha: 0.4)),
                        ),
                        onPressed: onIncreaseFont,
                        child: Text('A+', style: TextStyle(color: readerTheme.text)),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 行高间距
            Row(
              children: [
                Text('行距', style: TextStyle(fontSize: 13, color: readerTheme.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: readerTheme.subText.withValues(alpha: 0.2),
                      thumbColor: AppColors.primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: lineHeight,
                      min: 1.2,
                      max: 2.2,
                      divisions: 5,
                      // 拖动前锚定阅读位置，松手后统一还原，避免连续拖动时页面抖动
                      onChangeStart: (_) => onLineHeightChangeStart(),
                      onChanged: onLineHeightChanged,
                      onChangeEnd: (_) => onLineHeightChangeEnd(),
                    ),
                  ),
                ),
                Text(
                  '${lineHeight.toStringAsFixed(1)}x',
                  style: TextStyle(fontSize: 12, color: readerTheme.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
