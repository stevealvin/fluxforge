// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/data/library/history_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/features/library/history/history_center_page.dart';
import 'package:fluxforge/shared/widgets/filter_pill_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() async {
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
    if (!getIt.isRegistered<HistoryService>()) {
      getIt.registerSingleton<HistoryService>(HistoryService());
    }
    await AppStorage.clear();
    await playHistoryService.clear();
    await pumpEventQueue();
  });

  /// 播一条影视 + 一条小说，供筛选断言
  Future<void> seedRecords() async {
    await playHistoryService.upsert(
      PlayRecord(
        id: 'https://x/1',
        title: '流光纪元',
        mediaType: 'novel',
        episodeName: '第 3 章',
        updatedAt: DateTime(2026, 9, 21),
      ),
    );
    await playHistoryService.upsert(
      PlayRecord(
        id: 'https://x/2',
        title: '极光电影',
        mediaType: 'video',
        episodeName: '第 2 集',
        updatedAt: DateTime(2026, 9, 20),
      ),
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const HistoryCenterPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('类型筛选挂在顶栏下沿（与收藏页同一套胶囊）', (WidgetTester tester) async {
    await seedRecords();
    await pumpPage(tester);

    expect(find.byType(FilterPillBar), findsOneWidget);
    // 关键：它在 AppBar 内（吸顶），而不是像原先那样挂在列表里随内容滚走
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(FilterPillBar),
      ),
      findsOneWidget,
    );
  });

  testWidgets('点击类型胶囊后只保留该类记录', (WidgetTester tester) async {
    await seedRecords();
    await pumpPage(tester);

    expect(find.text('流光纪元'), findsOneWidget);
    expect(find.text('极光电影'), findsOneWidget);

    // 必须限定在筛选条内：记录卡自己的类型标签同样写着「影视」
    await tester.tap(
      find.descendant(
        of: find.byType(FilterPillBar),
        matching: find.text('影视'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('极光电影'), findsOneWidget);
    expect(find.text('流光纪元'), findsNothing);
  });
}
