import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/search/engines/search_concurrency_pool.dart';

void main() {
  group('SearchConcurrencyPool.run', () {
    test('空任务列表直接返回，不启动任何 Worker', () async {
      var invoked = 0;
      await SearchConcurrencyPool.run<int>(
        const [],
        action: (_) async => invoked++,
        shouldAbort: () => false,
      );
      expect(invoked, equals(0));
    });

    test('全部任务都被执行，且执行顺序与入参一致', () async {
      final done = <int>[];
      await SearchConcurrencyPool.run<int>(
        [1, 2, 3, 4, 5],
        action: (t) async => done.add(t),
        shouldAbort: () => false,
        maxConcurrency: 2,
      );
      expect(done, equals([1, 2, 3, 4, 5]));
    });

    test('并发度受上限约束，瞬时并发数绝不超过 maxConcurrency', () async {
      var running = 0;
      var peak = 0;
      final completer = Completer<void>();

      final future = SearchConcurrencyPool.run<int>(
        List.generate(10, (i) => i),
        action: (t) async {
          running++;
          peak = running > peak ? running : peak;
          await completer.future;
          running--;
        },
        shouldAbort: () => false,
        maxConcurrency: 3,
      );

      // 让出事件循环，等 Worker 全部启动并各自取到首个任务
      await Future<void>.delayed(Duration.zero);
      expect(peak, equals(3));

      completer.complete();
      await future;
    });

    test('shouldAbort 命中后立即停止后续任务调度', () async {
      var executed = 0;
      var aborted = false;

      await SearchConcurrencyPool.run<int>(
        List.generate(10, (i) => i),
        action: (t) async {
          executed++;
          if (executed == 2) aborted = true;
        },
        shouldAbort: () => aborted,
        maxConcurrency: 1,
      );

      // 串行模式下：执行完第 2 个任务后 shouldAbort 生效，剩下 8 个不再执行
      expect(executed, equals(2));
    });

    test('单个任务抛异常时向上传播，不静默吞掉', () async {
      expect(
        () => SearchConcurrencyPool.run<int>(
          [1],
          action: (_) async => throw StateError('boom'),
          shouldAbort: () => false,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
