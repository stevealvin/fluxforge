import 'package:flutter/services.dart' show HapticFeedback;
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/app_button.dart';

/// 弹出「二次确认」弹窗，返回用户是否确认（FluxForge 统一确认入口）
///
/// 全仓所有不可撤销 / 高影响操作统一走这里，消除各页面自行拼装 `AlertDialog`
/// 造成的三类分歧（此前实测存在）：危险色两套（`AppColors.danger` /
/// `Colors.redAccent`）、按钮文案三套、返回口径两套（调用方要不要处理 `null`）。
/// 本函数一次收敛：
///
/// - **配色**：破坏性操作一律 [AppColors.danger]，非破坏性走品牌主色；
/// - **口径**：返回**非空** `bool` —— 取消 / 系统返回 / 点弹窗外关闭都算 false，
///   调用方 `if (!confirmed) return;` 即可，无需判空；
/// - **职责**：弹窗只采集结论，**动作由调用方在确认后执行**（弹窗不碰业务，
///   因此不会出现「动作写在按钮里、失败后弹窗无处收敛」的半截状态）。
///
/// 典型用法：
/// ```dart
/// final confirmed = await showAppConfirmDialog(
///   context,
///   title: '清空全部历史',
///   message: '将同时清空「观看/阅读历史」与「搜索足迹」，该操作不可撤销。',
///   confirmText: '确认清空',
/// );
/// if (!confirmed) return;
/// await historyService.clearHistory();
/// ```
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确认',
  String cancelText = '取消',
  bool destructive = true,
  IconData? icon,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AppConfirmDialog(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
      destructive: destructive,
      icon: icon,
    ),
  );

  // 点弹窗外或系统返回键关闭时为 null —— 一律视为「未确认」
  return confirmed ?? false;
}

/// FluxForge 统一二次确认弹窗（也可直接当普通 Widget 使用，便于测试与预览）
///
/// 视觉规范：24px 大圆角表面、43px 强调色图标徽章、居中标题与说明、
/// 左右等宽双按钮（取消在左、确认在右）；自动适配「曜夜极光翡翠 / 纯净星暮白」双主题。
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = '确认',
    this.cancelText = '取消',
    this.destructive = true,
    this.icon,
  });

  /// 标题：一句话说明将要发生什么
  final String title;

  /// 说明正文：建议写清影响范围与是否可撤销
  final String message;

  /// 确认按钮文案（缺省「确认」；破坏性操作建议写明动词，如「删除」）
  final String confirmText;

  /// 取消按钮文案
  final String cancelText;

  /// 是否为破坏性操作（决定强调色与确认时的触觉反馈）
  final bool destructive;

  /// 顶部图标（缺省时按 [destructive] 自动取警示 / 询问图标）
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = destructive ? AppColors.danger : AppColors.primary;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 34, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : AppColors.lightCardBorder,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.42)
                  : const Color(0xFF0F172A).withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 强调色图标徽章：底色为强调色的低透明度衬底（深浅主题各取一档）
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon ??
                          (destructive
                              ? Ionicons.alertCircleOutline
                              : Ionicons.helpCircleOutline),
                      size: 24,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // 操作区：左右等宽、取消在左确认在右，保持全仓一致的点击热区与主次关系
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: cancelText,
                      variant: AppButtonVariant.outlined,
                      textColor: textSecondary,
                      isFullWidth: true,
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: confirmText,
                      color: accent,
                      isFullWidth: true,
                      onPressed: () {
                        // 破坏性操作在确认瞬间给一次中强度触觉反馈（与全仓 HapticFeedback 用法一致）
                        if (destructive) HapticFeedback.mediumImpact();
                        Navigator.pop(context, true);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
