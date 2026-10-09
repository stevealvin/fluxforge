import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/shared/widgets/app_confirm_dialog.dart';

/// 挂载一个「点按钮即弹确认」的宿主，返回收集确认结果的可变列表
Future<List<bool>> _pumpHost(
  WidgetTester tester, {
  bool destructive = true,
  String confirmText = '确认清空',
  bool settle = true,
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // 只推进到过渡途中：供「入场动画」用例观察动画中间态
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }
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

  testWidgets('入场带缩放淡入（不依赖 material_ui 那套无过渡的 DialogRoute）', (WidgetTester tester) async {
    await _pumpHost(tester, settle: false);

    // 我们注入的 ScaleTransition 应处在 < 1 的缩放上。
    // 这条是回归保护 —— 若有人把实现改回 `showDialog`，
    // material_ui 的 DialogRoute 会把 transitionBuilder 原样返回（硬切出现），此断言即失败。
    final animating = tester
        .widgetList<ScaleTransition>(find.byType(ScaleTransition))
        .any((transition) => transition.scale.value < 0.999);
    expect(animating, isTrue, reason: '弹窗应当处于缩放入场过程中');

    await tester.pumpAndSettle();
    expect(find.byType(AppConfirmDialog), findsOneWidget);
  });

  testWidgets('超长正文限高可滚动，不会把弹窗撑出屏幕', (WidgetTester tester) async {
    final longMessage = List.generate(
      40,
      (i) => '第 $i 行说明文字，用于验证超长正文的限高与滚动。',
    ).join('\n');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showAppConfirmDialog(
                  context,
                  title: '超长说明',
                  message: longMessage,
                  confirmText: '我知道了',
                ),
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();

    expect(find.byType(AppConfirmDialog), findsOneWidget);

    // 正文被包在限高滚动区内，且高度确实被压在上限以内
    final scrollView = find.descendant(
      of: find.byType(AppConfirmDialog),
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollView, findsOneWidget);
    expect(tester.getSize(scrollView).height, lessThanOrEqualTo(220.5));

    // 关键行为：按钮仍完整落在视口内且可点 —— 弹窗没有被超长正文顶出屏幕
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(AppConfirmDialog), findsNothing);
  });
}
