import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/shared/widgets/app_delete_snack_bar.dart';

/// 删除类底部提示的统一契约
///
/// 1. 5 秒自动消失（各页不再各定 1.5 / 4 秒）；
/// 2. 只有可恢复的删除才出现「撤销」。
void main() {
  Future<void> show(WidgetTester tester, {VoidCallback? onUndo}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showDeleteSnackBar(
                  context,
                  message: '已删除测试条目',
                  onUndo: onUndo,
                ),
                child: const Text('delete'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('5 秒后自动消失', (tester) async {
    await show(tester);
    expect(find.text('已删除测试条目'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('已删除测试条目'), findsOneWidget, reason: '5 秒窗口内必须还在，否则来不及点撤销');

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('已删除测试条目'), findsNothing, reason: '到时自动消失');
  });

  testWidgets('可恢复的删除给出「撤销」并可回调', (tester) async {
    var undone = 0;
    await show(tester, onUndo: () => undone++);

    expect(find.text('撤销'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pump();

    expect(undone, 1);
  });

  testWidgets('不可恢复的删除不摆「撤销」', (tester) async {
    await show(tester);
    expect(find.text('撤销'), findsNothing);
  });
}
