// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/shared/media_favorite_actions.dart';

MediaEpisode _ep(String title) =>
    MediaEpisode(title: title, url: 'https://example.com/$title');

MediaDetailData _data({
  String title = '流光测试剧集',
  String url = 'https://example.com/detail/1',
  String cover = '',
  MediaType type = MediaType.video,
  List<MediaEpisode> items = const [],
  List<MediaEpisode> chapters = const [],
}) {
  return MediaDetailData(
    title: title,
    url: url,
    cover: cover,
    mediaType: type,
    items: items,
    chapters: chapters,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() async {
    if (!getIt.isRegistered<FavoriteService>()) {
      getIt.registerSingleton<FavoriteService>(FavoriteService());
    }
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
    if (!getIt.isRegistered<RuleService>()) {
      getIt.registerSingleton<RuleService>(RuleService());
    }
    await AppStorage.clear();
    await favoriteService.clearFavorites();
    await playHistoryService.clear();
    await pumpEventQueue();
  });

  group('唯一键（与下载任务、消费记录三处同源）', () {
    test('优先取 url', () {
      expect(
        MediaFavoriteActions.key(_data(url: 'https://x/a'), '兜底标题'),
        'https://x/a',
      );
    });

    test('url 为空时回退标题', () {
      expect(
        MediaFavoriteActions.key(_data(url: '', title: ''), '兜底标题'),
        '兜底标题',
      );
    });
  });

  group('latestEpisodeOf', () {
    test('视频取 items 末项标题', () {
      final data = _data(items: [_ep('第01集'), _ep('第12集')]);
      expect(MediaFavoriteActions.latestEpisodeOf(data), '第12集');
    });

    test('小说优先取 chapters 末项标题', () {
      final data = _data(
        type: MediaType.novel,
        chapters: [_ep('第1章'), _ep('第9章')],
        items: [_ep('干扰项')],
      );
      expect(MediaFavoriteActions.latestEpisodeOf(data), '第9章');
    });

    test('无子项时返回空串（不编造最新集）', () {
      expect(MediaFavoriteActions.latestEpisodeOf(_data()), '');
    });
  });

  group('toggle', () {
    test('首次收藏写入真实进度与类型，再次调用则取消', () async {
      const url = 'https://x/book/1';
      await playHistoryService.upsert(
        PlayRecord(
          id: url,
          title: '流光纪元',
          mediaType: 'novel',
          episodeName: '第 3 章',
          updatedAt: DateTime(2026, 9, 21),
        ),
      );

      final data = _data(
        url: url,
        title: '流光纪元',
        type: MediaType.novel,
        chapters: [_ep('第1章'), _ep('第5章')],
      );

      expect(
        await MediaFavoriteActions.toggle(data: data, rule: null),
        '已加入收藏，追更已开启',
      );

      final item = favoriteService.favorites.single;
      expect(item.id, url);
      expect(item.mediaType, 'novel');
      expect(item.latestEpisode, '第5章');
      expect(item.lastEpisode, '第 3 章', reason: '进度必须来自消费记录，而不是最新集');

      expect(
        await MediaFavoriteActions.toggle(data: data, rule: null),
        '已取消收藏',
      );
      expect(favoriteService.favorites, isEmpty);
    });

    test('无法识别媒体（无 url 且无标题）时返回失败文案且不写入', () async {
      expect(
        await MediaFavoriteActions.toggle(
          data: _data(url: '', title: ''),
          rule: null,
        ),
        '无法识别该媒体，收藏失败',
      );
      expect(favoriteService.favorites, isEmpty);
    });
  });

  group('probeLatest（不联网的早退路径）', () {
    test('未绑定规则时直接返回 null', () async {
      final item = FavoriteItem(
        id: 'https://x/1',
        title: 'A',
        updatedAt: DateTime(2026, 9, 21),
      );
      expect(await MediaFavoriteActions.probeLatest(item), isNull);
    });

    test('标识不是可访问 URL 时返回 null', () async {
      final item = FavoriteItem(
        id: '标题兜底键',
        title: 'A',
        ruleId: '1',
        updatedAt: DateTime(2026, 9, 21),
      );
      expect(await MediaFavoriteActions.probeLatest(item), isNull);
    });
  });

  test('ruleOf：规则库不存在该 id 时返回 null', () {
    final item = FavoriteItem(
      id: 'https://x/1',
      title: 'A',
      ruleId: '不存在的规则',
      updatedAt: DateTime(2026, 9, 21),
    );
    expect(MediaFavoriteActions.ruleOf(item), isNull);
  });
}
