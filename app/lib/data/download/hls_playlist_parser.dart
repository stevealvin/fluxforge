/// HLS (m3u8) 清单解析与本地化改写（纯逻辑 · 无 IO · 可单测）
///
/// **职责边界**：本解析器只负责「读清单、找出所有需要落盘的远程资源、
/// 生成指向本地文件的清单」。**解密不在这里做** —— AES-128 的 key 同样会被下载到本地
/// 并改写进清单，最终交给 FFmpeg 的 `crypto` 协议去解密，避免在 Dart 侧重复实现
/// 分片解密与 IV 推导。
///
/// ### 覆盖范围
/// - master playlist（多码率）：取出的全部 variant 清单 URL 由调用方递归解析；
/// - media playlist：`#EXTINF` 之后的分片 URI，支持绝对 / 相对路径；
/// - `#EXT-X-KEY` / `#EXT-X-SESSION-KEY` / `#EXT-X-MAP` 属性中的 `URI="..."`；
/// - CRLF 与 LF 混用、行首尾空白、空行。
///
/// ### 已知限制（v1）
/// - `#EXT-X-MEDIA`（独立音轨 / 字幕轨子清单）不下载，多音轨源暂不支持；
/// - 直播流（无 `#EXT-X-ENDLIST`）不适用离线下载场景。
class HlsPlaylistParser {
  const HlsPlaylistParser._();

  /// 解析清单文本
  ///
  /// [baseUri] 用于把清单里的相对地址解析成绝对地址 ——
  /// 分片与密钥经常以相对路径出现，漏掉这一步会直接 404。
  static HlsPlaylist parse(String text, Uri baseUri) {
    bool isMaster = false;
    final uris = <String>[];
    final resources = <String>{};

    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          isMaster = true;
        }
        // KEY / SESSION-KEY / MAP 的 URI 同样需要本地化（解密交给 FFmpeg）
        if (line.startsWith('#EXT-X-KEY') ||
            line.startsWith('#EXT-X-SESSION-KEY') ||
            line.startsWith('#EXT-X-MAP')) {
          for (final uri in extractAttributeUris(line)) {
            resources.add(_absolute(uri, baseUri));
          }
        }
        continue;
      }

      // 非注释非空行都是 URI：master 里是码率子清单，media 里是分片
      final absolute = _absolute(line, baseUri);
      uris.add(absolute);
      resources.add(absolute);
    }

    return HlsPlaylist(
      isMaster: isMaster,
      variantUrls: isMaster ? uris : const <String>[],
      segmentUrls: isMaster ? const <String>[] : uris,
      resourceUrls: resources.toList(growable: false),
    );
  }

  /// 从 `#EXT-X-...` 属性行中提取所有 `URI="..."`
  static List<String> extractAttributeUris(String attributeLine) {
    final result = <String>[];
    for (final m in RegExp(r'URI="([^"]+)"').allMatches(attributeLine)) {
      final value = m.group(1)?.trim() ?? '';
      // 空 URI 或 data: 内联资源无需下载
      if (value.isEmpty || value.startsWith('data:')) continue;
      result.add(value);
    }
    return result;
  }

  /// 把清单中的远程地址改写为本地相对路径
  ///
  /// [remoteToLocal] 的键是**绝对化后**的远程地址（与 [parse] 产出的口径一致），
  /// 值是本地文件相对于清单所在目录的路径。
  static String rewriteToLocal(
    String text,
    Uri baseUri,
    Map<String, String> remoteToLocal,
  ) {
    if (remoteToLocal.isEmpty) return text;

    final buffer = StringBuffer();
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) {
        buffer.writeln();
        continue;
      }

      if (line.startsWith('#')) {
        var rewritten = line;
        for (final uri in extractAttributeUris(line)) {
          final local = remoteToLocal[_absolute(uri, baseUri)];
          if (local != null) {
            rewritten = rewritten.replaceAll('URI="$uri"', 'URI="$local"');
          }
        }
        buffer.writeln(rewritten);
        continue;
      }

      buffer.writeln(remoteToLocal[_absolute(line, baseUri)] ?? line);
    }
    return buffer.toString();
  }

  /// 相对路径 → 绝对路径（已是绝对地址时原样返回）
  static String _absolute(String uri, Uri baseUri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return uri;
    if (parsed.isAbsolute && parsed.scheme.isNotEmpty) return uri;
    return baseUri.resolve(uri).toString();
  }
}

/// 一次 HLS 清单解析的结果
class HlsPlaylist {
  const HlsPlaylist({
    required this.isMaster,
    required this.variantUrls,
    required this.segmentUrls,
    required this.resourceUrls,
  });

  /// 是否为多码率 master 清单
  final bool isMaster;

  /// master 时的码率子清单 URL（由调用方递归解析）
  final List<String> variantUrls;

  /// media 时的分片 URL（按播放顺序，已绝对化）
  final List<String> segmentUrls;

  /// 需要本地化的全部远程资源（分片 + 密钥 + 初始化段），去重保序、已绝对化
  final List<String> resourceUrls;
}
