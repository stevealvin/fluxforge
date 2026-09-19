/// 视频离线下载的 FFmpeg 命令构造与日志解析（纯逻辑 · 无 IO · 可单测）
///
/// 单独抽出的理由：FFmpeg 命令是一个纯字符串，**参数顺序、引号转义、HTTP 头传递方式**
/// 一旦写错，只会在真机上表现为「下载失败」或「视频无声」这类难以定位的现象。
/// 抽成纯函数后可以用单测把所有转义分支固定下来。
class FfmpegCommandBuilder {
  const FfmpegCommandBuilder._();

  /// HLS 输入所需的协议白名单
  ///
  /// - `crypto`：AES-128 加密分片（大量站点的 m3u8 都带 `#EXT-X-KEY`，缺它必失败）；
  /// - `data`：内联的密钥 / 初始化段；
  /// - 其余为常规网络协议。
  static const String protocolWhitelist = 'file,http,https,tcp,tls,crypto,data';

  /// 构造「下载并封装为 MP4」的 FFmpeg 命令
  ///
  /// 关键参数：
  /// - `-y`：覆盖残留文件，保证重试时不因文件已存在而失败；
  /// - `-c copy`：只做封装不做转码，耗时完全取决于网络；
  /// - `-bsf:a aac_adtstoasc`：修正 HLS 的 AAC 封装，**缺失会导致产出的 MP4 在部分播放器上无声**；
  /// - `-movflags +faststart`：把 moov 前置，保证边下边播与拖动流畅。
  ///
  /// 选项作用域严格遵循 FFmpeg 规则：`-protocol_whitelist` 与 HTTP 头属**输入侧**选项，
  /// 必须排在 `-i` 之前；编码与封装选项属**输出侧**，排在 `-i` 之后。
  static String buildDownload({
    required String url,
    required String outputPath,
    Map<String, String> headers = const {},
  }) {
    return <String>[
      '-y',
      '-protocol_whitelist', _quote(protocolWhitelist),
      ...buildHeaderArgs(headers),
      '-i', _quote(url),
      '-c', 'copy',
      '-bsf:a', 'aac_adtstoasc',
      '-movflags', '+faststart',
      _quote(outputPath),
    ].join(' ');
  }

  /// 把 HTTP 头拆成 FFmpeg 参数
  ///
  /// 优先使用专用选项（`-user_agent` / `-referer`）—— 这是最可靠的传递方式，
  /// 不需要处理 CRLF 分隔；**其余头（典型是 Cookie）才拼进 `-headers`**，
  /// 并按 FFmpeg 约定以 CRLF 分隔、且末尾同样补一个 CRLF。
  ///
  /// 返回值可直接展开进命令行；无有效头时返回空列表。
  static List<String> buildHeaderArgs(Map<String, String> headers) {
    final dedicated = <String>[];
    final extras = <String>[];

    headers.forEach((rawKey, rawValue) {
      final key = rawKey.trim();
      final value = rawValue.trim();
      // 空键或空值一律丢弃：拼进命令只会污染参数
      if (key.isEmpty || value.isEmpty) return;

      final lower = key.toLowerCase();
      if (lower == 'user-agent') {
        dedicated.addAll(['-user_agent', _quote(value)]);
      } else if (lower == 'referer' || lower == 'referrer') {
        dedicated.addAll(['-referer', _quote(value)]);
      } else {
        // 保留原始大小写：HTTP 头名大小写不敏感，但保持原样便于排查
        extras.add('$key: $value');
      }
    });

    if (extras.isNotEmpty) {
      dedicated.addAll(['-headers', _quote('${extras.join('\r\n')}\r\n')]);
    }
    return dedicated;
  }

  /// 构造「合并本地 HLS 分片」的命令
  ///
  /// 与 [buildDownload] 的区别：输入与输出都已在本地，协议白名单收窄为
  /// `file,crypto,data`（不再需要网络协议），也无需任何 HTTP 头 ——
  /// 分片与密钥均已由调用方落盘，解密仍由 FFmpeg 的 `crypto` 协议完成。
  static String buildLocalMerge({
    required String playlistPath,
    required String outputPath,
  }) {
    return <String>[
      '-y',
      '-protocol_whitelist', _quote('file,crypto,data'),
      '-i', _quote(playlistPath),
      '-c', 'copy',
      '-bsf:a', 'aac_adtstoasc',
      '-movflags', '+faststart',
      _quote(outputPath),
    ].join(' ');
  }

  /// 从 FFmpeg 日志中解析媒体总时长
  ///
  /// FFmpeg 开始处理时会输出形如 `Duration: 00:12:34.56, start: 0.000000, bitrate: ...`
  /// 的摘要行。借此拿到总时长即可把 `Statistics.getTime()` 换算成百分比，
  /// **无需额外发起 FFprobe 请求** —— 对需要防盗链头的源，FFprobe 也无法带上请求头，
  /// 走日志解析反而是唯一可行的途径。
  static Duration? parseDurationFromLog(String line) {
    final match =
        RegExp(r'Duration:\s*(\d+):(\d{2}):(\d{2})\.(\d{1,3})').firstMatch(line);
    if (match == null) return null;

    final hours = int.tryParse(match.group(1)!) ?? 0;
    final minutes = int.tryParse(match.group(2)!) ?? 0;
    final seconds = int.tryParse(match.group(3)!) ?? 0;
    // 小数位可能是 1~3 位，先右补齐到 3 位再截取，避免把 .5 当成 5ms
    final fraction = match.group(4)!.padRight(3, '0').substring(0, 3);
    final millis = int.tryParse(fraction) ?? 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    );
  }

  /// 计算当前项（单个视频）的下载进度（0.0 ~ 1.0）
  ///
  /// 总时长未知时返回 null —— 调用方据此展示「不确定进度」，
  /// **不要伪造 0.0**，否则用户会误以为下载卡死。
  static double? progressRatio({
    required int processedMillis,
    Duration? totalDuration,
  }) {
    if (totalDuration == null) return null;
    final total = totalDuration.inMilliseconds;
    if (total <= 0) return null;
    return (processedMillis / total).clamp(0.0, 1.0);
  }

  /// FFmpeg 命令行要求含特殊字符的参数用双引号包裹
  ///
  /// URL 常带 `&`、输出路径可能含空格与中文，不加引号会被解析成多个参数。
  static String _quote(String value) => '"${value.replaceAll('"', r'\"')}"';
}
