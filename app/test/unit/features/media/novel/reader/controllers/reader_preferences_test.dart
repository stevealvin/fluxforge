// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/reader_preferences.dart';
import 'package:fluxforge/features/media/novel/reader/models/page_turn_mode.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 阅读偏好持久化测试
///
/// 聚焦三件事：键名与取值的往返一致性、类型正确（字号 / 行距为 double）、
/// 以及**未持久化与脏数据的回落语义**（前者保持 null 不覆盖默认值，后者回落到安全默认）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('未持久化时所有字段为 null（不覆盖页面默认值）', () async {
    final snapshot = await ReaderPreferences.load();

    expect(snapshot.isEmpty, isTrue);
    expect(snapshot.fontSize, isNull);
    expect(snapshot.lineHeight, isNull);
    expect(snapshot.theme, isNull);
    expect(snapshot.pageMode, isNull);
  });

  test('字号与行距按 double 往返', () async {
    await ReaderPreferences.saveFontSize(22);
    await ReaderPreferences.saveLineHeight(1.9);

    final snapshot = await ReaderPreferences.load();

    expect(snapshot.fontSize, 22);
    expect(snapshot.lineHeight, 1.9);
    // 未设置的项仍为 null
    expect(snapshot.theme, isNull);
    expect(snapshot.pageMode, isNull);
  });

  test('护眼底色按名称往返', () async {
    final target = ReaderTheme.values.last;
    await ReaderPreferences.saveTheme(target);

    expect((await ReaderPreferences.load()).theme, target);
  });

  test('翻页模式按标识往返（纵向 / 横向）', () async {
    await ReaderPreferences.savePageMode(PageTurnMode.verticalScroll);
    expect(
      (await ReaderPreferences.load()).pageMode,
      PageTurnMode.verticalScroll,
    );

    await ReaderPreferences.savePageMode(PageTurnMode.horizontal);
    expect((await ReaderPreferences.load()).pageMode, PageTurnMode.horizontal);
  });

  test('无法识别的配色名回落到 parchment', () async {
    await AppStorage.setString(ReaderPreferences.themeKey, 'not-a-theme');

    expect((await ReaderPreferences.load()).theme, ReaderTheme.parchment);
  });

  test('无法识别的翻页模式标识回落到横向', () async {
    await AppStorage.setString(ReaderPreferences.pageModeKey, 'weird');

    expect((await ReaderPreferences.load()).pageMode, PageTurnMode.horizontal);
  });
}
