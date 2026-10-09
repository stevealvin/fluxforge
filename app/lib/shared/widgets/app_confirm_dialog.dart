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
  // 为什么不用 `showDialog`：material_ui 的 `DialogRoute` 把 transitionBuilder 写死成
  // 「原样返回 child」（见其 dialog.dart 的 `_buildMaterialDialogTransitions`），
  // 弹窗是**硬切出现**的 —— 这正是本弹窗此前缺少「浮入感」的根因。
  // 因此这里直接构造 `RawDialogRoute` 自行接管入场/退场动画（缩放 + 淡入）。
  //
  // 注：`RawDialogRoute` 由 widgets 层提供，会自行捕获 `InheritedTheme`，
  // 因此弹窗内的主题与 `showDialog` 路径完全一致。
  final confirmed = await Navigator.of(context, rootNavigator: true).push<bool>(
    RawDialogRoute<bool>(
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(
        context,
      ).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.52),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          // 从 0.92 起手：静态的「放大弹出」显得笨重，
          // 轻微起手才像卡片"浮"到位，配合 easeOutCubic 收尾更轻快
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) => AppConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        destructive: destructive,
        icon: icon,
      ),
    ),
  );

  // 点弹窗外或系统返回键关闭时为 null —— 一律视为「未确认」
  return confirmed ?? false;
}

/// FluxForge 统一二次确认弹窗（也可直接当普通 Widget 使用，便于测试与预览）
///
/// 视觉规范（第二版，2026-10 重设计）：
/// - **表面**：26px 大圆角；顶部一层强调色微光向下淡出 —— 卡片不再是一块死色，
///   而有明确的"光从上方来"的层次；
/// - **图标徽章**：54px squircle（圆角 18）+ 强调色对角渐变 + 同色柔光，
///   替代原先的纯色正圆，质感更接近现代卡片式弹窗；
/// - **文字**：18px 加粗标题 + 13.5px/1.6 正文，正文限高可滚动，长文案不会撑破弹窗；
/// - **操作区**：左右等宽，取消为柔和底色（无描边），确认为强调色填充 + 同色光晕，
///   破坏性操作在确认瞬间给一次中强度触觉反馈；
/// - 自动适配「曜夜极光翡翠 / 纯净星暮白」双主题。
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
    // 渐变副色：危险取更亮的红、常规取浅翡翠，让徽章有微光层次而非一块平色
    final accentSoft = destructive
        ? const Color(0xFFF87171)
        : (isDark ? AppColors.primaryGlow : AppColors.primaryLight);

    final surface = isDark ? AppColors.darkCard : AppColors.lightSurface;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    // 取消按钮的柔和底色：白面板上取比面板深一档的 slate，深色面板上取白色低透明
    final cancelBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : AppColors.lightSurfaceVariant;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      child: ConstrainedBox(
        // 限定宽度区间：文案很短时也不至于缩成一条，过长时也不会顶到屏幕边
        constraints: const BoxConstraints(minWidth: 292, maxWidth: 356),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  accent.withValues(alpha: isDark ? 0.13 : 0.07),
                  surface,
                ),
                surface,
              ],
              stops: const [0.0, 0.5],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.lightCardBorder,
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.50)
                    : const Color(0xFF0F172A).withValues(alpha: 0.14),
                blurRadius: 38,
                spreadRadius: -2,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标徽章：squircle + 对角渐变 + 同色柔光
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: isDark ? 0.34 : 0.22),
                        accentSoft.withValues(alpha: isDark ? 0.16 : 0.10),
                      ],
                    ),
                    border: Border.all(
                      color: accent.withValues(alpha: isDark ? 0.32 : 0.18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: isDark ? 0.26 : 0.16),
                        blurRadius: 20,
                        spreadRadius: -6,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon ??
                        (destructive
                            ? Ionicons.alertCircleOutline
                            : Ionicons.helpCircleOutline),
                    size: 26,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 9),
                // 正文限高可滚动：说明很长的场景（如备份还原）不会把弹窗撑出屏幕
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.6,
                        color: textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // 操作区：左右等宽、取消在左确认在右，保持全仓一致的点击热区与主次关系
                Row(
                  children: [
                    Expanded(
                      child: AppButton.tonal(
                        label: cancelText,
                        color: cancelBg,
                        textColor: textSecondary,
                        borderRadius: 14,
                        isFullWidth: true,
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      // 确认键外套一层同色光晕：让主操作在柔和底色上"亮"出来
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.32),
                              blurRadius: 16,
                              spreadRadius: -4,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: AppButton(
                          label: confirmText,
                          color: accent,
                          borderRadius: 14,
                          isFullWidth: true,
                          onPressed: () {
                            // 破坏性操作在确认瞬间给一次中强度触觉反馈（与全仓 HapticFeedback 用法一致）
                            if (destructive) HapticFeedback.mediumImpact();
                            Navigator.pop(context, true);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
