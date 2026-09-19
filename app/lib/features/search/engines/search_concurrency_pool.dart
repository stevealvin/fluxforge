/// 受控并发池（纯异步调度，无第三方依赖，可纯 Dart 单测）
///
/// 开源阅读同款流式调度思路：不让 N 个规则源同时唤醒沙箱，
/// 而是维持固定数量的 Worker 依次取任务，避免瞬时内存与网络峰值。
class SearchConcurrencyPool {
  const SearchConcurrencyPool._();

  /// 默认并发度
  static const int defaultConcurrency = 3;

  /// 以受控并发度依次跑完 [tasks]
  ///
  /// - [shouldAbort] 在每个任务开始前校验，命中即立即停止后续调度（用户点「停止」或轮次已过期）；
  /// - 任务按列表顺序被 Worker 竞争消费，因此单个死链源最多占用一个 Worker，不会阻塞全局。
  static Future<void> run<T>(
    List<T> tasks, {
    required Future<void> Function(T task) action,
    required bool Function() shouldAbort,
    int maxConcurrency = defaultConcurrency,
  }) async {
    if (tasks.isEmpty) return;

    final iterator = tasks.iterator;
    Future<void> worker() async {
      while (iterator.moveNext()) {
        if (shouldAbort()) break;
        await action(iterator.current);
      }
    }

    final workerCount = tasks.length < maxConcurrency ? tasks.length : maxConcurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));
  }
}
