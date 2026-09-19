import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/app_button.dart';

/// 规则调试页顶部操作区：测试关键字输入框 + 开始/停止按钮
///
/// 纯展示 + 回调上抛：输入框与焦点由宿主持有，本组件只负责焦点高亮与按钮语义。
class RuleTestControlHeader extends StatelessWidget {
  const RuleTestControlHeader({
    super.key,
    required this.isDark,
    required this.controller,
    required this.focusNode,
    required this.isTesting,
    required this.onChanged,
    required this.onStart,
    required this.onStop,
  });

  final bool isDark;
  final TextEditingController controller;

  /// 由宿主持有，用于驱动输入框边框的聚焦高亮
  final FocusNode focusNode;

  /// 测试进行中：按钮变为红色「停止」
  final bool isTesting;

  /// 输入变化回调：仅用于驱动清空按钮的显隐重建
  final ValueChanged<String> onChanged;

  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightSurface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          // 纯净单圆角搜索关键词输入框
          Expanded(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBg : AppColors.lightBg,
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
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '输入测试关键词...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.primary),
                  suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  suffixIcon: controller.text.isNotEmpty
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            controller.clear();
                            onChanged('');
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.clear_rounded, size: 15),
                          ),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  // 清除所有继承边框，杜绝双圆角重叠
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
                onSubmitted: (_) {
                  if (!isTesting) onStart();
                },
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 测试启动/停止按钮
          AppButton.compact(
            label: isTesting ? '停止' : '开始测试',
            icon: isTesting
                ? const Icon(Ionicons.squareOutline, size: 14)
                : const Icon(Ionicons.playOutline, size: 14),
            color: isTesting ? Colors.redAccent : AppColors.primary,
            onPressed: isTesting ? onStop : onStart,
          ),
        ],
      ),
    );
  }
}
