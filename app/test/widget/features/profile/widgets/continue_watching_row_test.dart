import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/features/profile/widgets/continue_watching_row.dart';

PlayRecord _record(String id, String title) {
  return PlayRecord(
    id: id,
    title: title,
    mediaType: 'video',
    episodeName: '第 1 集',
    episodeIndex: 0,
    totalEpisodes: 12,
    positionSeconds: 30,
    durationSeconds: 120,
    updatedAt: DateTime(2026, 9, 21),
  );
}

Future<void> _pump(WidgetTester tester, List<PlayRecord> records) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ContinueWatchingRow(records: records),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('横滑卡片高度收敛为 136，内容不溢出', (WidgetTester tester) async {
    await _pump(tester, [_record('a', '流光测试剧集'), _record('b', '暗夜剧场')]);

    expect(find.text('流光测试剧集'), findsOneWidget);
    expect(find.text('暗夜剧场'), findsOneWidget);

    // 横滑 ListView 的 cross-axis 是紧约束：列表高度即卡片高度
    expect(tester.getSize(find.byType(ListView)).height, 136);

    // 高度改小后最容易出问题的就是内容溢出（黄黑条纹 + 异常）
    expect(tester.takeException(), isNull);
  });

  testWidgets('无记录时展示空态引导卡片', (WidgetTester tester) async {
    await _pump(tester, const []);

    expect(find.text('还没有观看记录'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
