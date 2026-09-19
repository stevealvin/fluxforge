// ignore_for_file: depend_on_referenced_packages
// 自定义站点存储服务测试：URL 规范化与校验、增删改、持久化往返
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/data/sites/site_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // AppStorage 的静态句柄会固定首次使用的 platform 实例，替换 instance 不足以隔离，
    // 必须显式清空数据，否则前序用例的持久化内容会泄漏到后续用例
    await AppStorage.clear();
  });

  /// 等待构造时的异步加载完成
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  group('normalizeUrl / isValidUrl', () {
    test('缺省 scheme 自动补 https，已有 scheme 与首尾空白原样保留', () {
      expect(SiteStore.normalizeUrl('example.com'), 'https://example.com');
      expect(SiteStore.normalizeUrl('  example.com  '), 'https://example.com');
      expect(SiteStore.normalizeUrl('http://a.com'), 'http://a.com');
      expect(SiteStore.normalizeUrl('https://a.com/x?y=1'), 'https://a.com/x?y=1');
      expect(SiteStore.normalizeUrl(''), '');
    });

    test('仅 http / https 且 host 非空视为合法', () {
      expect(SiteStore.isValidUrl('example.com'), isTrue);
      expect(SiteStore.isValidUrl('https://example.com/path?q=1'), isTrue);
      expect(SiteStore.isValidUrl('https://'), isFalse);
      expect(SiteStore.isValidUrl('ftp://example.com'), isFalse);
      expect(SiteStore.isValidUrl('   '), isFalse);
    });
  });

  group('SiteStore', () {
    test('新增站点：补全地址、缺省名称用域名兜底、新项置顶', () async {
      final store = SiteStore();
      await settle();

      await store.add(name: '', url: 'b.example.com');
      await store.add(name: '甲', url: 'a.example.com');

      expect(store.sites.length, 2);
      expect(store.sites.first.name, '甲');
      expect(store.sites.first.url, 'https://a.example.com');
      expect(store.sites.last.name, 'b.example.com');
    });

    test('同地址重复添加不产生重复项（复用并置顶）', () async {
      final store = SiteStore();
      await settle();

      await store.add(name: '甲', url: 'a.example.com');
      await store.add(name: '乙', url: 'https://a.example.com');

      expect(store.sites.length, 1);
      expect(store.sites.first.name, '乙');
    });

    test('编辑与删除按 id 精确定位', () async {
      final store = SiteStore();
      await settle();

      await store.add(name: '甲', url: 'a.example.com');
      final id = store.sites.first.id;

      await store.update(id, name: '甲改', url: 'c.example.com');
      expect(store.sites.first.name, '甲改');
      expect(store.sites.first.url, 'https://c.example.com');

      await store.remove(id);
      expect(store.sites, isEmpty);
    });

    test('落盘后新实例可读回同一份数据', () async {
      final store = SiteStore();
      await settle();
      await store.add(name: '影视站', url: 'v.example.com');

      final reloaded = SiteStore();
      await settle();

      expect(reloaded.sites.length, 1);
      expect(reloaded.sites.first.name, '影视站');
      expect(reloaded.sites.first.url, 'https://v.example.com');
    });
  });
}
