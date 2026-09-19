import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/app_button.dart';

/// 搜索页顶部搜索栏（返回键 + 输入框 + 搜索/停止键）
///
/// 纯展示 + 回调上抛：输入框状态由宿主持有，本组件只负责焦点高亮与按钮语义。
class SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SearchAppBar({
    super.key,
    required this.isDark,
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.hintText,
    required this.isLoading,
    required this.onBack,
    required this.onClear,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCancel,
  });

  final bool isDark;
  final TextEditingController controller;

  /// 由宿主持有，用于驱动输入框边框的聚焦高亮
  final FocusNode focusNode;

  /// 由入参关键词决定（携带初始关键词时不再自动弹键盘）
  final bool autofocus;

  final String hintText;

  /// 检索进行中：按钮变为红色「停止」
  final bool isLoading;

  final VoidCallback onBack;

  /// 清空输入框（宿主需同时把结果集切回历史面板）
  final VoidCallback onClear;

  /// 输入变化回调：仅用于驱动清空按钮的显隐重建
  final ValueChanged<String> onChanged;

  /// 键盘「搜索」键提交
  final ValueChanged<String> onSubmitted;

  /// 中止本轮跨源并发检索
  final VoidCallback onCancel;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: onBack,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: '返回',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: focusNode.hasFocus
                        ? AppColors.primary
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    width: focusNode.hasFocus ? 1.2 : 0.8,
                  ),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    suffixIcon: controller.text.isNotEmpty
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onClear,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.clear_rounded, size: 16),
                            ),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    // 彻底清除内层所有边框与背景继承，杜绝内外双重圆角嵌套叠加的 UI 缺陷
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
                  ),
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            AppButton.compact(
              label: isLoading ? '停止' : '搜索',
              color: isLoading ? Colors.redAccent.withValues(alpha: 0.85) : null,
              onPressed: isLoading ? onCancel : () => onSubmitted(controller.text),
            ),
          ],
        ),
      ),
    );
  }
}
