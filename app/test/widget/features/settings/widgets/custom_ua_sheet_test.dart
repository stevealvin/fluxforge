import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/features/settings/widgets/custom_ua_sheet.dart';

/// 面板调用的收集器（面板关闭是异步的，断言要在关闭之后读同一对象）
class _Collector {
  String? result;
  bool saved = false;
  String? savedValue;
}

/// 自定义 User-Agent 底部面板
///
/// 与「备份恢复」同形态：顶部两角 取消 / 确认、输入框贴底。
/// 契约要点：**留空是合法输入**（表示恢复内置默认），所以确认不能禁用。
void main() {
  Future<void> openSheet(
    WidgetTester tester,
    _Collector collector, {
    String initialValue = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  collector.result = await showCustomUaSheet(
                    context,
                    initialValue: initialValue,
                    onSave: (ua) async {
                      collector.saved = true;
                      collector.savedValue = ua;
                    },
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('回填当前 UA；确认后交给宿主保存并返回该值', (tester) async {
    final collector = _Collector();
    await openSheet(tester, collector, initialValue: 'UA-old/1.0');

    expect(find.text('自定义 User-Agent'), findsOneWidget);
    expect(find.text('UA-old/1.0'), findsOneWidget, reason: '打开即回填当前值');

    await tester.enterText(find.byType(TextField), 'UA-new/2.0');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing, reason: '确认后面板收起');
    expect(collector.saved, isTrue);
    expect(collector.savedValue, 'UA-new/2.0');
    expect(collector.result, 'UA-new/2.0');
  });

  testWidgets('一键恢复默认后留空也能确认（不是哑交互）', (tester) async {
    final collector = _Collector();
    await openSheet(tester, collector, initialValue: 'UA-old/1.0');

    await tester.tap(find.text('恢复默认'));
    await tester.pump();
    expect(find.text('UA-old/1.0'), findsNothing, reason: '一键清空输入');

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing, reason: '空输入同样能确认收起');
    expect(collector.savedValue, isEmpty);
    expect(collector.result, isEmpty);
  });

  testWidgets('取消不写入任何设置', (tester) async {
    final collector = _Collector();
    await openSheet(tester, collector, initialValue: 'UA-old/1.0');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(collector.saved, isFalse);
    expect(collector.result, isNull);
    expect(find.byType(TextField), findsNothing);
  });
}
