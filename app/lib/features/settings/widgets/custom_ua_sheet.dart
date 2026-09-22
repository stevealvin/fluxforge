import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/app_button.dart';

/// 呼出「自定义 User-Agent」底部面板（取消 / 确认在顶部两角，输入框贴底）
///
/// 与备份恢复面板（`showRestoreBackupSheet`）同一交互形态：
/// - **顶部左右角常驻 取消 / 确认**，不再出现「点了没反应」的哑交互；
/// - **输入框贴底且随键盘上移**（`isScrollControlled` + `viewInsets`），
///   粘贴长 UA 串时不会被输入法遮挡；
/// - 两个快捷动作：粘贴剪贴板（UA 串通常是从别处复制的）与恢复内置默认。
///
/// 返回保存后的 UA（`''` 表示恢复内置默认）；用户取消返回 `null`。
///
/// 拆成独立 StatefulWidget 而非就地 `StatefulBuilder`：输入控制器必须**跟随面板
/// 自身销毁**释放 —— 若等 `showModalBottomSheet` 的 Future 完成后再 dispose，
/// 面板退场动画期间仍会重建并引用控制器，触发
/// `A TextEditingController was used after being disposed`。
Future<String?> showCustomUaSheet(
  BuildContext context, {
  required String initialValue,
  required Future<void> Function(String userAgent) onSave,
}) {
  return showModalBottomSheet<String>(
    context: context,
    // 面板需随键盘上移，故必须由自身控制滚动与高度
    isScrollControlled: true,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSurface
        : AppColors.lightSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _CustomUaSheetBody(initialValue: initialValue, onSave: onSave),
  );
}

/// 「自定义 User-Agent」面板主体（私有）
class _CustomUaSheetBody extends StatefulWidget {
  const _CustomUaSheetBody({required this.initialValue, required this.onSave});

  final String initialValue;
  final Future<void> Function(String userAgent) onSave;

  @override
  State<_CustomUaSheetBody> createState() => _CustomUaSheetBodyState();
}

class _CustomUaSheetBodyState extends State<_CustomUaSheetBody> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  /// 保存进行中：避免连点「确认」触发两次写入
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 保存并收起
  ///
  /// **留空是合法输入**（表示恢复内置默认标头），所以确认按钮始终可用 ——
  /// 这与备份面板「空文本没有意义」的取舍不同。
  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    final value = _controller.text.trim();
    try {
      await widget.onSave(value);
    } finally {
      if (mounted) Navigator.pop(context, value);
    }
  }

  /// 从剪贴板粘贴 UA 串
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _controller.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final borderColor = isDark
        ? AppColors.darkCardBorder
        : AppColors.lightCardBorder;

    return Padding(
      // 键盘弹出时整体上移，保证贴底的输入框始终可见
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          // 小屏或键盘弹起后可用高度不足时改为滚动，避免 RenderFlex 溢出
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ① 顶部：左取消 / 中标题 / 右确认
                Row(
                  children: [
                    AppButton.ghost(
                      label: '取消',
                      size: AppButtonSize.compact,
                      textColor: textSecondary,
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        '自定义 User-Agent',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    AppButton(
                      label: '确认',
                      size: AppButtonSize.compact,
                      onPressed: _saving ? null : _submit,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ② 说明
                Text(
                  '作用于规则页请求，以及图片、视频直链的伪装标头；留空即使用内置移动端标头。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 14),

                // ③ 输入区标题 + 快捷动作
                Row(
                  children: [
                    Text(
                      'UA 请求标头',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    AppButton(
                      label: '粘贴剪贴板',
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.mini,
                      icon: const Icon(Ionicons.clipboardOutline),
                      onPressed: _pasteFromClipboard,
                    ),
                    const SizedBox(width: 6),
                    AppButton(
                      label: '恢复默认',
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.mini,
                      icon: const Icon(Ionicons.refreshOutline),
                      onPressed: () => setState(_controller.clear),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ④ 贴底输入框（等宽字体便于核对长串）
                TextField(
                  controller: _controller,
                  minLines: 3,
                  maxLines: 6,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.5,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) ...\n'
                        '留空 = 使用内置标头',
                    hintStyle: const TextStyle(fontSize: 11, height: 1.5),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : AppColors.lightBg,
                    contentPadding: const EdgeInsets.all(12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: borderColor, width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
