import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/features/library/downloads/models/download_unit.dart';
import 'package:fluxforge/features/library/downloads/widgets/download_bar.dart';
import 'package:fluxforge/features/media/shared/media_download_sheet.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

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

  /// 单元卡片（卡片化后每项一张卡，用 key 精确定位，不再依赖系统 Checkbox）
  Finder unitCard(int index) => find.byKey(ValueKey('download_unit_$index'));

  Future<void> openSheet(
    WidgetTester tester, {
    List<DownloadUnit>? unitList,
    Future<String> Function(Set<int> selection)? onDownloadSelection,
    Future<List<int?>> Function()? probeUnitSizes,
    DownloadTask? Function()? taskOf,
    bool dark = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
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
                  taskOf: taskOf ?? () => null,
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
    expect(unitCard(0), findsNothing);
    expect(find.text('下载全部 3 集'), findsOneWidget);
  });

  testWidgets('勾选与全选都会实时反映到按钮与摘要', (tester) async {
    await openSheet(tester, onDownloadSelection: (_) async => 'ok');

    expect(find.text('已选 0 项'), findsOneWidget);

    await tester.tap(unitCard(0));
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

    await tester.tap(unitCard(0));
    await tester.pump();
    await tester.tap(unitCard(2));
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

    await tester.tap(unitCard(0));
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

    await tester.tap(unitCard(0));
    await tester.pump();

    expect(find.text('已选 1 项 · 大小未知'), findsOneWidget);
  });

  testWidgets('选集为紧凑网格：未选中无边框线，选中以主色边框（并加粗）表达', (tester) async {
    await openSheet(tester, onDownloadSelection: (_) async => 'ok');

    expect(find.byType(GridView), findsOneWidget, reason: '选集应为网格布局');

    final unselected = tester.widget<AppCard>(unitCard(0));
    expect(
      unselected.color,
      AppColors.darkCard,
      reason: '暗色下格子取面板（darkSurface）上一档底色，与面板分档',
    );
    expect(
      unselected.borderColor,
      Colors.transparent,
      reason: '未选中不画默认边框线（透明边框只为占位，避免切换时跳尺寸）',
    );

    await tester.tap(unitCard(0));
    await tester.pump();

    final selected = tester.widget<AppCard>(unitCard(0));
    expect(selected.borderColor, AppColors.primary, reason: '选中以主色边框表达');
    expect(
      selected.borderWidth,
      greaterThan(unselected.borderWidth),
      reason: '边框同时加粗，不单靠颜色区分',
    );
    expect(
      tester.widget<AppCard>(unitCard(1)).borderColor,
      isNot(AppColors.primary),
      reason: '未选中项不受影响',
    );
  });

  testWidgets('亮色下未选中格子不得与纯白面板同色（否则区块没有边界）', (tester) async {
    // 亮色面板是纯白，格子若也铺纯白且无边框，就完全看不出边界
    await openSheet(tester, dark: false, onDownloadSelection: (_) async => 'ok');

    final cell = tester.widget<AppCard>(unitCard(0));
    expect(
      cell.color,
      AppColors.lightSurfaceVariant,
      reason: '亮色用深一档的内嵌块底色界定区块',
    );
    expect(cell.color, isNot(AppColors.lightSurface));

    // 选中态与未选中仍可分
    await tester.tap(unitCard(0));
    await tester.pump();
    expect(
      tester.widget<AppCard>(unitCard(0)).color,
      isNot(cell.color),
      reason: '选中后底色变化',
    );
  });

  testWidgets('已有任务时「下载全部」入口不重复出现，改由状态条承担', (tester) async {
    final running = DownloadTask(
      id: 'book-1',
      title: '测试剧集',
      targetUrls: const ['https://example.com/1.mp4'],
      status: DownloadStatus.running,
      createdAt: DateTime(2026, 9, 22),
      updatedAt: DateTime(2026, 9, 22),
    );

    await openSheet(
      tester,
      onDownloadSelection: (_) async => 'ok',
      taskOf: () => running,
    );

    expect(
      find.text('下载全部 3 集'),
      findsNothing,
      reason: '未开始时入口在动作行；已开始后由状态条承担，避免同一动作两个入口',
    );
    expect(find.byType(DownloadBar), findsOneWidget);
  });
}
