/// 一次原生 HTTP 请求的执行记录
///
/// 由 `RuleEngine` 在每次请求结束（含失败）后经 `httpObserver` 抛出，
/// 供规则调试页的「网络」页展示。**生产运行时不产生任何记录** ——
/// 引擎保持「不知道自己正被调试」，与 `RuleTestActions` 采用注入入口
/// 而非改造引擎的边界一致。
///
/// 之所以要记录 [finalUrl] 与 [redirectCount]：规则调试里最常见的一类问题
/// 就是「以为请求的是 A，实际被跳到了 B」（http → https、旧路径 → 新路径、
/// 站点用了 302 而非直出），只有把跳转显式记下来才看得见。
class HttpRequestRecord {
  const HttpRequestRecord({
    required this.method,
    required this.url,
    required this.finalUrl,
    required this.statusCode,
    required this.elapsedMs,
    this.sizeBytes,
    this.redirectCount = 0,
    this.error,
  });

  /// 请求方法（GET / POST / ...）
  final String method;

  /// 规则里写明的原始 URL
  final String url;

  /// 跟随重定向后的最终 URL（未发生重定向时与 [url] 相同）
  final String finalUrl;

  /// 最终响应状态码；请求在拿到响应前就失败时为 0
  final int statusCode;

  /// 从发起到拿到响应的总耗时（含所有重定向往返）
  final int elapsedMs;

  /// 响应体大小（字节）。优先取 `content-length` 响应头，缺失时回退为
  /// 响应文本长度 —— 后者对中文是**字符数**而非字节数，会偏小，仅供量级参考。
  final int? sizeBytes;

  /// 跟随的重定向次数
  final int redirectCount;

  /// 失败原因（网络异常 / 超时等）；成功时为 null
  final String? error;

  /// 是否成功拿到一个非错误响应（2xx / 3xx 均视为拿到了响应）
  bool get isOk => error == null && statusCode > 0 && statusCode < 400;

  /// 是否发生了重定向（值得在列表里高亮）
  bool get hasRedirect => redirectCount > 0;

  /// 去掉协议与域名的请求路径，列表里比整条 URL 更好扫读
  String get displayPath {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.path.isEmpty) return url;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.path}$query';
  }

  /// 字节数的可读文案（KB / MB），未知时返回空串
  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
