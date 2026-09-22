/// 下载速率采样器（纯逻辑，可单测）
///
/// 按「一段区间内的字节 ÷ 区间时长」估算速率，而不是「上一块的字节 ÷ 上一块的耗时」——
/// 后者在分块 / 分片大小不均时会剧烈跳动，UI 上表现为数字乱闪。
///
/// 用法：每收到一段数据就 [add] 增量字节；满足 [interval] 时它返回新速率，
/// 返回 `null` 表示「本次不必更新 UI」（节流）。
///
/// 速率属**瞬时状态**：不参与持久化，暂停 / 重启后自然归零。
class DownloadRateMeter {
  DownloadRateMeter({this.interval = const Duration(milliseconds: 800)});

  /// 采样间隔：既是最小上报间隔，也是速率统计的区间长度
  ///
  /// 取 800ms：再短数字跳得厉害，再长会让「停下来了」这件事显得迟钝。
  final Duration interval;

  int _bytes = 0;
  DateTime? _windowStart;

  /// 累加 [delta] 字节；距窗口起点满 [interval] 时返回速率（字节/秒），否则 null
  double? add(int delta, DateTime now) {
    if (delta <= 0) return null;

    _bytes += delta;
    final start = _windowStart ??= now;
    final elapsed = now.difference(start);
    if (elapsed < interval) return null;

    final millis = elapsed.inMilliseconds;
    if (millis <= 0) return null;

    final speed = _bytes * 1000 / millis;
    // 窗口前移：以当前时刻为新起点，速率不会被整段历史拖住
    _bytes = 0;
    _windowStart = now;
    return speed;
  }

  /// 归零（暂停 / 任务收尾时调用）
  void reset() {
    _bytes = 0;
    _windowStart = null;
  }
}
