import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/shared/widgets/setting_tile.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child)),
  );
}

SettingRow _row({
  VoidCallback? onTap,
  String? value,
  Widget? trailing,
  bool busy = false,
}) {
  return SettingRow(
    icon: Icons.settings_outlined,
    color: AppColors.primary,
    title: '沙箱请求超时时限',
    subtitle: '复杂网络源的等待上限',
    onTap: onTap,
    value: value,
    trailing: trailing,
    busy: busy,
  );
}

void main() {
  testWidgets('行展示图标徽章、标题与说明', (WidgetTester tester) async {
    await _pump(tester, _row(onTap: () {}));

    expect(find.text('沙箱请求超时时限'), findsOneWidget);
    expect(find.text('复杂网络源的等待上限'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('onTap 非空且无自绘尾部时补右箭头（可点即给提示）', (WidgetTester tester) async {
    await _pump(tester, _row(onTap: () {}));

    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsOneWidget);
  });

  testWidgets('不可点的行（onTap 为 null）不画箭头', (WidgetTester tester) async {
    await _pump(tester, _row());

    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
  });

  testWidgets('开关 / 下拉等自绘尾部不画箭头（避免同一尾部两种提示）', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _row(
        onTap: () {},
        trailing: Switch(value: true, onChanged: (_) {}),
      ),
    );

    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
  });

  testWidgets('数值右置，且可与自绘尾部共存', (WidgetTester tester) async {
    await _pump(
      tester,
      _row(
        onTap: () {},
        value: '1.2 MB',
        trailing: const Icon(Icons.check_circle_rounded),
      ),
    );

    expect(find.text('1.2 MB'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('busy 时改显示进度环，数值与尾部都不渲染', (WidgetTester tester) async {
    await _pump(
      tester,
      _row(onTap: () {}, value: '统计中', busy: true),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('统计中'), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
  });

  testWidgets('SettingSection 为相邻子项插入分隔线：n 个子项恰好 n-1 条', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const SettingSection(
        children: [Text('一'), Text('二'), Text('三')],
      ),
    );

    expect(find.byType(Divider), findsNWidgets(2));
  });
}
