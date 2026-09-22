import 'package:material_ui/material_ui.dart';

/// 删除类操作的统一底部提示
///
/// 两条约定：
/// 1. **5 秒后自动消失**：删除是需要「后悔时间」的操作 —— 太短来不及点撤销，
///    太长又会挡住后续操作，因此全仓统一 5 秒，不再各页自定（此前有 1.5 秒、
///    默认 4 秒等多种口径）；
/// 2. **只有可恢复的删除才摆「撤销」**：传 [onUndo] 才出现该按钮。
///    不可恢复的删除（清空日志、删除离线文件等）只给提示，
///    不摆一个点了没用的按钮。
///
/// 调用方若需要等待用户反馈（例如「撤销窗口结束后再真正落盘」），
/// 可以 `await` 返回的控制器上的 `closed`。
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showDeleteSnackBar(
  BuildContext context, {
  required String message,
  VoidCallback? onUndo,
  String undoLabel = '撤销',
}) {
  final messenger = ScaffoldMessenger.of(context);
  // 连续删除时只保留最后一条，避免提示排队把前一条的正确性拖成过期信息
  messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      action: onUndo == null
          ? null
          : SnackBarAction(label: undoLabel, onPressed: onUndo),
    ),
  );
}
