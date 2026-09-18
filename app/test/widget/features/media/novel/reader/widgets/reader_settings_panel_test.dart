import 'package:flutter_test/flutter_test.dart';
// 项目使用 vendored material_ui（自带一份 material 源码），
// 必须与组件同源导入，否则 Material 祖先校验（debugCheckHasMaterial）无法匹配
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/novel/reader/models/page_turn_mode.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_settings_panel.dart';

/// 排版设置面板组件测试
///
/// 该组件是纯展示 + 回调上抛，因此测试聚焦两件事：
/// 1. 状态回显（字号 / 行距 / 当前选中项）；
/// 2. 交互语义 —— 尤其是「点已选中的翻页模式不触发切换」这条防抖约定。
void main() {
  /// 面板返回 Positioned，必须挂到 Stack 内
  Future<void> pumpPanel(
    WidgetTester tester, {
    ReaderTheme theme = ReaderTheme.parchment,
    double fontSize = 18,
    double lineHeight = 1.6,
    PageTurnMode pageMode = PageTurnMode.horizontal,
    ValueChanged<ReaderTheme>? onThemeSelected,
    ValueChanged<PageTurnMode>? onPageModeSelected,
    VoidCallback? onDecreaseFont,
    VoidCallback? onIncreaseFont,
    VoidCallback? onLineHeightChangeStart,
    ValueChanged<double>? onLineHeightChanged,
    VoidCallback? onLineHeightChangeEnd,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ReaderSettingsPanel(
                readerTheme: theme,
                fontSize: fontSize,
                lineHeight: lineHeight,
                pageMode: pageMode,
                onThemeSelected: onThemeSelected ?? (_) {},
                onPageModeSelected: onPageModeSelected ?? (_) {},
                onDecreaseFont: onDecreaseFont ?? () {},
                onIncreaseFont: onIncreaseFont ?? () {},
                onLineHeightChangeStart: onLineHeightChangeStart ?? () {},
                onLineHeightChanged: onLineHeightChanged ?? (_) {},
                onLineHeightChangeEnd: onLineHeightChangeEnd ?? () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('回显当前字号与行距', (tester) async {
    await pumpPanel(tester, fontSize: 20, lineHeight: 1.8);

    expect(find.text('20 px'), findsOneWidget);
    expect(find.text('1.8x'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('字号加减按钮分别上抛对应回调', (tester) async {
    var increased = 0;
    var decreased = 0;

    await pumpPanel(
      tester,
      onIncreaseFont: () => increased++,
      onDecreaseFont: () => decreased++,
    );

    await tester.tap(find.text('A+'));
    await tester.pump();
    await tester.tap(find.text('A-'));
    await tester.pump();

    expect(increased, 1);
    expect(decreased, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择其它护眼底色时回传对应主题', (tester) async {
    ReaderTheme? picked;
    final target = ReaderTheme.values.last;

    await pumpPanel(tester, onThemeSelected: (th) => picked = th);

    await tester.tap(find.text(target.name));
    await tester.pump();

    expect(picked, target);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击当前已选中的翻页模式不触发切换', (tester) async {
    var calls = 0;

    await pumpPanel(
      tester,
      pageMode: PageTurnMode.values.first,
      onPageModeSelected: (_) => calls++,
    );

    // 第一个 Chip 即当前选中项：ChoiceChip 点击时回调参数为 !selected，
    // 面板必须据此拦截，避免「点自己反而切走模式」
    await tester.tap(find.byType(ChoiceChip).first);
    await tester.pump();

    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击未选中的翻页模式触发切换', (tester) async {
    PageTurnMode? picked;

    await pumpPanel(
      tester,
      pageMode: PageTurnMode.values.first,
      onPageModeSelected: (mode) => picked = mode,
    );

    await tester.tap(find.byType(ChoiceChip).last);
    await tester.pump();

    expect(picked, PageTurnMode.values.last);
    expect(tester.takeException(), isNull);
  });
}
