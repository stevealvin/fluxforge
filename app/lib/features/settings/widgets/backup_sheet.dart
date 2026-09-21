import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/settings/controllers/backup_actions.dart';
import 'package:fluxforge/shared/widgets/app_button.dart';

/// 还原动作签名：把备份 JSON 文本按指定策略还原，返回**面向用户的提示文案**
///
/// 以回调注入（见 [showBackupSheet]）：面板不解析 DI、不直接调用备份服务。
typedef BackupRestoreAction = Future<String> Function({
  required String jsonStr,
  required bool merge,
});

/// 呼出「数据全量备份与还原」底部操作面板
///
/// 统一「我的」页与系统设置页的备份入口，彻底消除此前两份逐行重复的实现。
///
/// **接线归宿主**：[onExport] / [onRestore] 未传时走真实服务
/// （默认实现见 `controllers/backup_actions.dart`）—— 与
/// `ChapterContentPipeline(parseRule: …)`、`RuleTestActions` 同一「默认接线 + 可注入」模式。
/// 传入可控实现即可脱离 DI 直接测本面板。
Future<void> showBackupSheet(
  BuildContext context, {
  Future<void> Function()? onExport,
  BackupRestoreAction? onRestore,
}) async {
  final export = onExport ?? exportBackupData;
  final restore = onRestore ?? restoreBackupFromText;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSurface
        : AppColors.lightSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                '数据全量备份与还原',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            // 1. 一键导出备份包
            ListTile(
              leading: const Icon(
                Ionicons.cloudUploadOutline,
                color: AppColors.primary,
              ),
              title: const Text('一键导出备份数据包'),
              subtitle: const Text(
                '将规则库、收藏、搜索历史与观看进度打包为 JSON 并分享/保存至本地',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                try {
                  await export();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('导出备份失败: $e')));
                  }
                }
              },
            ),
            // 2. 从 JSON 文本恢复
            ListTile(
              leading: const Icon(
                Ionicons.cloudDownloadOutline,
                color: Colors.amber,
              ),
              title: const Text('从 JSON 文本/剪贴板恢复'),
              subtitle: const Text(
                '解析备份文件，支持合并追加或全量覆盖',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                showRestoreBackupSheet(context, onRestore: restore);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// 呼出「恢复备份数据」底部面板（取消 / 确认在顶部两角，输入框贴底）
///
/// 与原先的居中对话框相比，这里改掉三件事：
/// - **顶部左右角常驻 [取消] / [确认]**：确认按钮在输入为空时**禁用**，
///   不再出现「点了没反应、也没有任何提示」的哑交互；
/// - **输入框贴底且随键盘上移**（`isScrollControlled` + `viewInsets`），
///   粘贴长 JSON 时不会被输入法遮挡；
/// - **还原策略由复选框改为分段切换**：默认「合并导入」，切到「完全覆盖」时
///   整段转为危险色，语义（是否会清空现有数据）一眼可辨。
///
/// 还原动作由调用方注入（默认见 [showBackupSheet]），面板只负责收集输入与展示结果；
/// 剪贴板读取属于面板自身的交互细节，故留在原处。
Future<void> showRestoreBackupSheet(
  BuildContext context, {
  required BackupRestoreAction onRestore,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    // 面板需随键盘上移，故必须由自身控制滚动与高度
    isScrollControlled: true,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkSurface
        : AppColors.lightSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RestoreBackupSheetBody(onRestore: onRestore),
  );
}

/// 「恢复备份数据」面板主体（私有）
///
/// 拆成 StatefulWidget 而不是就地 `StatefulBuilder`：输入控制器必须**跟随面板自身
/// 销毁**释放 —— 若等 `showModalBottomSheet` 的 Future 完成后再 dispose，面板退场
/// 动画期间仍会重建并引用控制器，触发
/// `A TextEditingController was used after being disposed`。
class _RestoreBackupSheetBody extends StatefulWidget {
  const _RestoreBackupSheetBody({required this.onRestore});

  final BackupRestoreAction onRestore;

  @override
  State<_RestoreBackupSheetBody> createState() =>
      _RestoreBackupSheetBodyState();
}

class _RestoreBackupSheetBodyState extends State<_RestoreBackupSheetBody> {
  final TextEditingController _controller = TextEditingController();

  /// 还原策略：true = 合并导入（保留现有数据），false = 完全覆盖
  bool _mergeMode = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 提交还原：先取出 messenger 并收起面板，再执行动作、反馈结果
  ///
  /// 面板自身 context 在 pop 之后即失效，故 messenger 必须在收起之前取出。
  Future<void> _submit() async {
    final jsonStr = _controller.text.trim();
    if (jsonStr.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);

    final message = await widget.onRestore(jsonStr: jsonStr, merge: _mergeMode);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// 从剪贴板粘贴备份文本
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || !mounted) return;
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
    final canSubmit = _controller.text.trim().isNotEmpty;

    /// 还原策略分段项（选中态用策略语义色：合并=主色，覆盖=危险色）
    Widget strategySegment(
      String label,
      bool selected,
      bool isDanger,
      VoidCallback onTap,
    ) {
      final activeColor = isDanger ? AppColors.danger : AppColors.primary;
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? activeColor.withValues(alpha: isDark ? 0.20 : 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? activeColor : textSecondary,
              ),
            ),
          ),
        ),
      );
    }

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
                        '恢复备份数据',
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
                      onPressed: canSubmit ? _submit : null,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ② 说明
                Text(
                  '粘贴导出的 FluxForge 备份 JSON 文本，选择还原策略后确认：',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 14),

                // ③ 还原策略分段切换 + 当前策略语义提示
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      strategySegment(
                        '合并导入',
                        _mergeMode,
                        false,
                        () => setState(() => _mergeMode = true),
                      ),
                      strategySegment(
                        '完全覆盖',
                        !_mergeMode,
                        true,
                        () => setState(() => _mergeMode = false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _mergeMode ? '保留现有数据，仅追加备份中新增的条目' : '清空现有数据，完全以备份内容为准',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: _mergeMode ? textSecondary : AppColors.danger,
                  ),
                ),
                const SizedBox(height: 16),

                // ④ 输入区标题 + 剪贴板入口
                Row(
                  children: [
                    Text(
                      '备份 JSON 文本',
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
                  ],
                ),
                const SizedBox(height: 8),

                // ⑤ 贴底输入框（等宽字体便于核对 JSON 结构）
                TextField(
                  controller: _controller,
                  minLines: 4,
                  maxLines: 7,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.5,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '{\n  "app": "FluxForge",\n  "data": { ... }\n}',
                    hintStyle: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
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
