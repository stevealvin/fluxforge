// ignore_for_file: depend_on_referenced_packages
// DownloadService「URL 过期刷新」机制测试
//
// 端到端覆盖直链路径：源站 403 → 触发 onUrlExpired → 用新地址重试。
// HLS 合并依赖 FFmpeg 原生库，测试环境不可用，故 HLS 仅覆盖请求层行为。
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/core/network/api_client.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';

/// 可编程假响应适配器：按 URL 子串映射状态码，并记录全部请求顺序
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._routes);

  /// url 子串 → 状态码；>=400 抛 DioException.badResponse，否则返回 200 + 字节体
  final Map<String, int> _routes;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.toString());
    for (final entry in _routes.entries) {
      if (options.uri.toString().contains(entry.key)) {
        final status = entry.value;
        if (status >= 400) {
          throw DioException.badResponse(
            statusCode: status,
            requestOptions: options,
            response: Response<dynamic>(
              requestOptions: options,
              statusCode: status,
            ),
          );
        }
        return ResponseBody.fromBytes(
          Uint8List.fromList(List<int>.filled(16, 0x7F)),
          200,
        );
      }
    }
    throw StateError('未配置的路由: ${options.uri}');
  }

  @override
  void close({bool force = false}) {}
}

class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

late String _docsPath;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final temp = await Directory.systemTemp.createTemp('fluxforge_dl_test');
    _docsPath = temp.path;
    PathProviderPlatform.instance = _FakePathProvider();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  DownloadService buildService({
    required _StubAdapter adapter,
    Future<String?> Function(DownloadTask, int, String)? onUrlExpired,
  }) {
    final apiClient = ApiClient();
    apiClient.dio.httpClientAdapter = adapter;
    return DownloadService(
      ruleService: RuleService(),
      apiClient: apiClient,
      onUrlExpired: onUrlExpired,
    );
  }

  Future<void> waitUntil(
    DownloadService service,
    String bookId,
    bool Function(DownloadTask) predicate,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final task = service.taskOf(bookId);
      if (task != null && predicate(task)) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('等待任务状态超时');
  }

  Future<DownloadTask> startTask(
    DownloadService service,
    String bookId,
    String url,
  ) {
    return service.startVideoDownload(
      rule: Rule(
        id: 1,
        name: '测试源',
        baseUrl: 'https://example.com',
        type: 'video',
        code: '',
      ),
      bookId: bookId,
      title: 'URL 刷新测试剧',
      cover: '',
      episodes: [MediaEpisode(title: '第 1 集', url: url)],
    );
  }

  group('isAuthExpiredStatus', () {
    test('401 / 403 / 410 判定为 URL 失效', () {
      expect(DownloadService.isAuthExpiredStatus(401), isTrue);
      expect(DownloadService.isAuthExpiredStatus(403), isTrue);
      expect(DownloadService.isAuthExpiredStatus(410), isTrue);
    });

    test('超时类、服务端错误与正常响应不判定为失效', () {
      expect(DownloadService.isAuthExpiredStatus(200), isFalse);
      expect(DownloadService.isAuthExpiredStatus(400), isFalse);
      expect(DownloadService.isAuthExpiredStatus(404), isFalse);
      expect(DownloadService.isAuthExpiredStatus(500), isFalse);
      expect(DownloadService.isAuthExpiredStatus(null), isFalse);
    });
  });

  group('onUrlExpired 端到端（直链）', () {
    test('403 → 回调返回新地址 → 用新 URL 续传成功且进度不丢', () async {
      final adapter = _StubAdapter({'stale': 403, 'fresh': 200});
      final refreshCalls = <String>[];
      final service = buildService(
        adapter: adapter,
        onUrlExpired: (task, index, staleUrl) async {
          refreshCalls.add('$index:$staleUrl');
          return 'https://cdn.example.com/fresh/video.mp4';
        },
      );
      await service.init();

      await startTask(
        service,
        'refresh-ok',
        'https://cdn.example.com/stale/video.mp4',
      );
      await waitUntil(service, 'refresh-ok', (t) => t.isFinished);

      // 恰好刷新一次，且拿到的是完整旧地址
      expect(refreshCalls, ['0:https://cdn.example.com/stale/video.mp4']);
      // 重试确实请求了新地址
      expect(adapter.requested.where((u) => u.contains('fresh')), isNotEmpty);
      // 新地址已登记回任务，后续「重试失败」会用它
      expect(
        service.taskOf('refresh-ok')!.targetUrls.first,
        contains('fresh'),
      );
      // 产物正常落盘
      expect(await service.localVideoPath('refresh-ok', 0), isNotNull);
    });

    test('回调返回 null → 该集按普通失败处理', () async {
      final adapter = _StubAdapter({'stale': 403});
      var calls = 0;
      final service = buildService(
        adapter: adapter,
        onUrlExpired: (task, index, staleUrl) async {
          calls++;
          return null;
        },
      );
      await service.init();

      await startTask(
        service,
        'refresh-null',
        'https://cdn.example.com/stale/video.mp4',
      );
      await waitUntil(
        service,
        'refresh-null',
        (t) => t.status == DownloadStatus.failed,
      );

      expect(calls, 1);
      expect(adapter.requested.length, 1);
      expect(service.taskOf('refresh-null')!.failed, contains(0));
    });

    test('新地址再次 403 → 不二次刷新（防死循环）', () async {
      final adapter = _StubAdapter({'stale': 403, 'fresh': 403});
      var calls = 0;
      final service = buildService(
        adapter: adapter,
        onUrlExpired: (task, index, staleUrl) async {
          calls++;
          return 'https://cdn.example.com/fresh/video.mp4';
        },
      );
      await service.init();

      await startTask(
        service,
        'refresh-twice-403',
        'https://cdn.example.com/stale/video.mp4',
      );
      await waitUntil(
        service,
        'refresh-twice-403',
        (t) => t.status == DownloadStatus.failed,
      );

      // 初次 + 刷新重试各一次，回调只触发一次
      expect(adapter.requested.length, 2);
      expect(calls, 1);
      expect(service.taskOf('refresh-twice-403')!.failed, contains(0));
    });

    test('未注册回调 → 403 行为与既往一致（直接失败）', () async {
      final adapter = _StubAdapter({'stale': 403});
      final service = buildService(adapter: adapter);
      await service.init();

      await startTask(
        service,
        'no-refresher',
        'https://cdn.example.com/stale/video.mp4',
      );
      await waitUntil(
        service,
        'no-refresher',
        (t) => t.status == DownloadStatus.failed,
      );

      expect(adapter.requested.length, 1);
      expect(service.taskOf('no-refresher')!.failed, contains(0));
    });
  });
}
