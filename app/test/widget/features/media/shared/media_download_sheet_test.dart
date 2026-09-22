import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/features/library/downloads/models/download_unit.dart';
import 'package:fluxforge/features/media/shared/media_download_sheet.dart';

/// 离线下载面板的「选集下载」交互
///
/// 面板是纯展示 + 回调组件：任务订阅、动作与大小探测全部由宿主注入，
/// 因此这里可以脱 DI 直接验证 —— 勾选、全选、清空、下载选中、大小摘要。
void main() {
  final tasks = ValueNotifier<List<DownloadTask>>(const []);

  List<DownloadUnit> units(int count) => [
    for (int i = 0; i < count; i++)
      DownloadUnit(index: i, title: '第 ${i + 1} 集'),
  ];

  Future<void> openSheet(
    WidgetTester tester, {
    List<DownloadUnit>? unitList,
    Future<String> Function(Set<int> selection)? onDownloadSelection,
    Future<List<int?>> Function()? probeUnitSizes,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showMediaDownloadSheet(
                  context,
                  title: '测试剧集',
                  bookId: 'book-1',
                  unitLabel: '集',
                  tasks: tasks,
                  taskOf: () => null,
                  onAction: (_) async => '已加入下载队列',
                  units: unitList ?? units(3),
                  onDownloadSelection: onDownloadSelection,
                  probeUnitSizes: probeUnitSizes,
                ),
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

  testWidgets('有可下载单元时展示选集区，并给出「下载全部 N 集」', (tester) async {
    await openSheet(tester, onDownloadSelection: (_) async => 'ok');

    expect(find.text('选集下载'), findsOneWidget);
    expect(find.text('第 1 集'), findsOneWidget);
    expect(find.text('第 3 集'), findsOneWidget);
    expect(find.text('下载全部 3 集'), findsOneWidget, reason: '全部下载入口保持可用');
    expect(find.text('下载选中'), findsOneWidget, reason: '未勾选时按钮为占位文案');
  });

  testWidgets('宿主不提供选集能力时，不出现选集区', (tester) async {
    await openSheet(tester);

    expect(find.text('选集下载'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('下载全部 3 集'), findsOneWidget);
  });

  testWidgets('勾选与全选都会实时反映到按钮与摘要', (tester) async {
    await openSheet(tester, onDownloadSelection: (_) async => 'ok');

    expect(find.text('已选 0 项'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('下载选中（1 项）'), findsOneWidget);
    expect(find.text('已选 1 项 · 大小未知'), findsOneWidget, reason: '无探测时如实说未知');

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('下载选中（3 项）'), findsOneWidget);
    expect(find.text('已选 3 项 · 大小未知'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump();
    expect(find.text('下载选中'), findsOneWidget);
    expect(find.text('已选 0 项'), findsOneWidget);
  });

  testWidgets('「下载选中」把勾选集合交给宿主', (tester) async {
    Set<int>? received;
    await openSheet(
      tester,
      onDownloadSelection: (selection) async {
        received = selection;
        return '已加入下载队列（2 项）';
      },
    );

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();
    await tester.tap(find.text('下载选中（2 项）'));
    await tester.pumpAndSettle();

    expect(received, {0, 2});
    expect(find.text('已加入下载队列（2 项）'), findsOneWidget);
  });

  testWidgets('未勾选时「下载选中」不触发回调', (tester) async {
    var called = false;
    await openSheet(
      tester,
      onDownloadSelection: (_) async {
        called = true;
        return 'ok';
      },
    );

    await tester.tap(find.text('下载选中'), warnIfMissed: false);
    await tester.pump();

    expect(called, isFalse);
  });

  testWidgets('提供大小探测时显示预计体积，未知项以「以上」标注', (tester) async {
    await openSheet(
      tester,
      onDownloadSelection: (_) async => 'ok',
      probeUnitSizes: () async => [500 * 1024 * 1024, null, 500 * 1024 * 1024],
    );

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    expect(find.text('已选 1 项 · 预计 500.0 MB'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选 3 项 · 预计 1000.0 MB 以上'), findsOneWidget);
  });

  testWidgets('探测失败或全未知时只报数量，不编造体积', (tester) async {
    await openSheet(
      tester,
      onDownloadSelection: (_) async => 'ok',
      probeUnitSizes: () async => [null, null, null],
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    expect(find.text('已选 1 项 · 大小未知'), findsOneWidget);
  });
}
