import 'package:material_ui/material_ui.dart';

/// 阅读区三区点击热层：左 1/3 上一页、中 1/3 呼出菜单、右 1/3 下一页
///
/// 说明：热层位于正文之上，且**仅注册 onTap 手势**，因此可以稳定抢到单击事件，
/// 同时不干扰长按划词、拖动选择与滑动翻页手势。
class ReaderTapZones extends StatelessWidget {
  const ReaderTapZones({
    super.key,
    required this.onPreviousPage,
    required this.onToggleControls,
    required this.onNextPage,
  });

  /// 点击左侧 1/3：上一页
  final VoidCallback onPreviousPage;

  /// 点击中间 1/3：呼出 / 收起控制栏
  final VoidCallback onToggleControls;

  /// 点击右侧 1/3：下一页
  final VoidCallback onNextPage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 33,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onPreviousPage,
          ),
        ),
        Expanded(
          flex: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onToggleControls,
          ),
        ),
        Expanded(
          flex: 33,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onNextPage,
          ),
        ),
      ],
    );
  }
}
