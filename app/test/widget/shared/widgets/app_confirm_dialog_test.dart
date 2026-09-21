import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/shared/widgets/app_confirm_dialog.dart';

/// 挂载一个「点按钮即弹确认」的宿主，返回收集确认结果的可变列表
Future<List<bool>> _pumpHost(
  WidgetTester tester, {
  bool destructive = true,
  String confirmText = '确认清空',
}) async {
  final results = <bool>[];

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                results.add(
                  await showAppConfirmDialog(
                    context,
                    title: '清空全部历史',
                    message: '将同时清空「观看/阅读历史」与「搜索足迹」，该操作不可撤销。',
                    confirmText: confirmText,
                    destructive: destructive,
                  ),
                );
              },
              child: const Text('触发'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('触发'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('确认弹窗渲染标题、正文与两端按钮', (WidgetTester tester) async {
    await _pumpHost(tester);

    expect(find.byType(AppConfirmDialog), findsOneWidget);
    expect(find.text('清空全部历史'), findsOneWidget);
    expect(find.text('将同时清空「观看/阅读历史」与「搜索足迹」，该操作不可撤销。'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确认清空'), findsOneWidget);
  });

  testWidgets('点确认返回 true 并关闭弹窗', (WidgetTester tester) async {
    final results = await _pumpHost(tester);

    await tester.tap(find.text('确认清空'));
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.byType(AppConfirmDialog), findsNothing);
  });

  testWidgets('点取消返回 false', (WidgetTester tester) async {
    final results = await _pumpHost(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(results, [false]);
  });

  testWidgets('点弹窗外关闭同样返回 false（调用方无需判空）', (WidgetTester tester) async {
    final results = await _pumpHost(tester);

    // 弹窗四周留白（insetPadding）之外即模态遮罩
    await tester.tapAt(const Offset(6, 6));
    await tester.pumpAndSettle();

    expect(results, [false]);
  });

  testWidgets('非破坏性确认同样可渲染与返回', (WidgetTester tester) async {
    final results = await _pumpHost(
      tester,
      destructive: false,
      confirmText: '立即清理',
    );

    expect(find.text('立即清理'), findsOneWidget);
    await tester.tap(find.text('立即清理'));
    await tester.pumpAndSettle();

    expect(results, [true]);
  });
}
