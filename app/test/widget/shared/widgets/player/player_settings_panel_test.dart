import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/shared/widgets/player/player_settings_panel.dart';

/// 播放设置开关行：说明文案可选
///
/// 锁定契约：`subtitle` 缺省时**只渲染标题**（不留空位、不渲染占位文本），
/// 这样自解释的开关行不会每行都挂一句噪音。
void main() {
  Future<void> pumpRow(WidgetTester tester, {String? subtitle}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: PlayerSettingSwitchRow(
            title: '长按快进',
            subtitle: subtitle,
            value: false,
            onChanged: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('不传说明时只渲染标题与开关', (tester) async {
    await pumpRow(tester);

    expect(find.text('长按快进'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(Text), findsOneWidget, reason: '没有说明文本，也不应有占位空文本');
  });

  testWidgets('传说明时标题与说明同时渲染', (tester) async {
    await pumpRow(tester, subtitle: '补充说明');

    expect(find.text('长按快进'), findsOneWidget);
    expect(find.text('补充说明'), findsOneWidget);
  });

  testWidgets('空字符串说明等同于不传', (tester) async {
    await pumpRow(tester, subtitle: '');

    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('开关回调正常上抛', (tester) async {
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: PlayerSettingSwitchRow(
            title: '长按快进',
            value: false,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(changed, isTrue);
  });
}
