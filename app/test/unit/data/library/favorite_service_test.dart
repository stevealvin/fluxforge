// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/data/library/favorite_service.dart';

const String _id = 'https://example.com/book/1';

FavoriteItem _item({
  String id = _id,
  String title = '流光纪元',
  String mediaType = 'novel',
  String lastEpisode = '',
  String latestEpisode = '',
  bool hasUpdate = false,
}) {
  return FavoriteItem(
    id: id,
    title: title,
    mediaType: mediaType,
    lastEpisode: lastEpisode,
    latestEpisode: latestEpisode,
    hasUpdate: hasUpdate,
    updatedAt: DateTime(2026, 9, 21),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  late FavoriteService service;

  setUp(() async {
    await AppStorage.clear();
    service = FavoriteService();
    await pumpEventQueue();
  });

  test('首次加载完成即置位 isLoaded（供页面区分「未加载」与「确实为空」）', () {
    expect(service.isLoaded, isTrue);
    expect(service.favorites, isEmpty);
  });

  test('添加 / 判定 / 移除 / 切换收藏闭环', () async {
    expect(await service.toggleFavorite(_item()), isTrue);
    expect(service.isFavorite(_id), isTrue);
    expect(service.favorites.length, 1);

    expect(await service.toggleFavorite(_item()), isFalse);
    expect(service.isFavorite(_id), isFalse);
    expect(service.favorites, isEmpty);
  });

  test('收藏写入后可被新实例从存储读回', () async {
    await service.addFavorite(_item(title: '追光者'));

    final reloaded = FavoriteService();
    await pumpEventQueue();

    expect(reloaded.favorites.single.title, '追光者');
  });

  test('markAsRead 只清红点，不改写「上次看到」（防伪造进度回归）', () async {
    await service.addFavorite(
      _item(lastEpisode: '第 3 章', latestEpisode: '第 9 章', hasUpdate: true),
    );

    await service.markAsRead(_id);

    final item = service.favorites.single;
    expect(item.hasUpdate, isFalse);
    expect(item.lastEpisode, '第 3 章', reason: '打开详情不应伪造观看进度');
    expect(item.latestEpisode, '第 9 章');
  });

  test('checkUpdates：源站最新 ≠ 本地真实进度时点亮红点', () async {
    await service.addFavorite(_item(lastEpisode: '第 3 章'));

    final count = await service.checkUpdates(
      probe: (item) async => '第 9 章',
      progressOf: (item) => '第 3 章',
    );

    expect(count, 1);
    final item = service.favorites.single;
    expect(item.latestEpisode, '第 9 章');
    expect(item.hasUpdate, isTrue);
  });

  test('checkUpdates：进度已追上最新时不点亮红点', () async {
    await service.addFavorite(_item(lastEpisode: '第 9 章'));

    final count = await service.checkUpdates(
      probe: (item) async => '第 9 章',
      progressOf: (item) => '第 9 章',
    );

    expect(count, 0);
    expect(service.favorites.single.hasUpdate, isFalse);
  });

  test('checkUpdates：单项探测异常不影响其余作品', () async {
    await service.addFavorite(
      _item(id: 'https://example.com/a', title: 'A', latestEpisode: '第 2 话'),
    );
    await service.addFavorite(
      _item(id: 'https://example.com/b', title: 'B', latestEpisode: '第 2 话'),
    );

    final count = await service.checkUpdates(
      probe: (item) async {
        if (item.title == 'A') throw StateError('源站超时');
        return '第 5 话';
      },
      progressOf: (item) => '第 2 话',
    );

    expect(count, 1, reason: 'A 探测失败保留原值、不误报；B 正常报更新');
    expect(
      service.favorites.firstWhere((e) => e.title == 'A').hasUpdate,
      isFalse,
    );
    expect(
      service.favorites.firstWhere((e) => e.title == 'B').hasUpdate,
      isTrue,
    );
  });

  test('checkUpdates：未注入探测器时退化为本地比对（不再恒为 0 的前提是有探测）', () async {
    await service.addFavorite(
      _item(lastEpisode: '第 5 章', latestEpisode: '第 5 章'),
    );

    expect(await service.checkUpdates(), 0);
  });

  test('clearFavorites 清空并持久化', () async {
    await service.addFavorite(_item());
    await service.clearFavorites();

    expect(service.favorites, isEmpty);
    final reloaded = FavoriteService();
    await pumpEventQueue();
    expect(reloaded.favorites, isEmpty);
  });
}
