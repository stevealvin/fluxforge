import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/features/settings/widgets/backup_sheet.dart';
import 'package:fluxforge/shared/widgets/app_button.dart';

/// 挂载宿主并打开「恢复备份数据」面板，返回还原调用记录
Future<List<({String jsonStr, bool merge})>> _openRestoreSheet(
  WidgetTester tester,
) async {
  final calls = <({String jsonStr, bool merge})>[];

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showRestoreBackupSheet(
                context,
                onRestore:
                    ({required String jsonStr, required bool merge}) async {
                      calls.add((jsonStr: jsonStr, merge: merge));
                      return '已恢复 3 组数据';
                    },
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  return calls;
}

/// 排空 SnackBar 的展示计时，避免测试结束时残留定时器
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('恢复备份面板：顶部两角是取消/确认，输入框贴底，空输入时确认不可点', (WidgetTester tester) async {
    await _openRestoreSheet(tester);

    expect(find.text('恢复备份数据'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // 空输入 → 确认禁用（不再出现「点了没反应」的哑交互）
    final confirmButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, '确认'),
    );
    expect(confirmButton.onPressed, isNull);

    // 取消 / 确认同处顶部一行，且输入框在其下方（贴底）
    final cancelCenter = tester.getCenter(find.text('取消'));
    final confirmCenter = tester.getCenter(find.text('确认'));
    final fieldCenter = tester.getCenter(find.byType(TextField));

    expect(cancelCenter.dy, closeTo(confirmCenter.dy, 1.0));
    expect(cancelCenter.dx, lessThan(confirmCenter.dx));
    expect(fieldCenter.dy, greaterThan(confirmCenter.dy));
  });

  testWidgets('输入 JSON 后可确认：按默认「合并导入」还原并提示结果', (WidgetTester tester) async {
    final calls = await _openRestoreSheet(tester);

    await tester.enterText(find.byType(TextField), '{"app":"FluxForge"}');
    await tester.pump();

    final confirmButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, '确认'),
    );
    expect(confirmButton.onPressed, isNotNull);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(calls.length, 1);
    expect(calls.single.jsonStr, '{"app":"FluxForge"}');
    expect(calls.single.merge, isTrue);
    expect(find.text('已恢复 3 组数据'), findsOneWidget);

    await _drainSnackBar(tester);
  });

  testWidgets('切到「完全覆盖」后按覆盖策略还原', (WidgetTester tester) async {
    final calls = await _openRestoreSheet(tester);

    await tester.enterText(find.byType(TextField), '{}');
    await tester.tap(find.text('完全覆盖'));
    await tester.pump();

    // 策略语义提示随选择切换
    expect(find.text('清空现有数据，完全以备份内容为准'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(calls.single.merge, isFalse);

    await _drainSnackBar(tester);
  });
}
