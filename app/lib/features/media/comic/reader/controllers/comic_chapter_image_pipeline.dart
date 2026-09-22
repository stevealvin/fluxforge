import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/core/utils/media_utils.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';

/// 章节图片解析：由调用方注入 —— 默认走沙箱 [RuleEngine.parse]
///
/// 与小说 `ChapterContentPipeline(parseRule: …)` 同一「默认实现在外、可注入可测」范式。
typedef ComicChapterParser = Future<Object?> Function(Rule rule, String url);

/// 「章节 → 图片列表」解析管线
///
/// ### 为什么需要这一层
/// 图片类作品有两种写法（见 [MediaContentShape]）：
///
/// - **图集**：detail 的 `items` 直接就是图片地址，不需要任何二次解析；
/// - **漫画**：detail 的 `items` / `groups` 只给**章节页地址**（如 `/chapter/53996`），
///   必须再 parse 一次，才能拿到该章的图片列表。
///
/// 少了这一跳，章节地址会被当成图片地址直接请求 —— 表现就是"图永远转不出来"。
///
/// ### 与小说正文管线的关系
/// 同构：注入 parse、按章解析、按需缓存、相邻预取、单章失败隔离，
/// 区别只在「一章的内容」从**文本**换成**图片地址列表**。刻意不共用一个类：
/// 小说那条还背着离线落盘、正文清洗等一整套语义，硬合会把两边都拧紧。
class ComicChapterImagePipeline {
  ComicChapterImagePipeline({
    ComicChapterParser? parser,
    this.cacheCapacity = 16,
  }) : _parser = parser ?? defaultParser;

  /// 默认解析实现（沙箱）
  static Future<Object?> defaultParser(Rule rule, String url) =>
      RuleEngine.parse(rule, url);

  final ComicChapterParser _parser;

  /// 内存缓存上限（章 → 图片列表）：来回翻看相邻章时命中即零等待
  final int cacheCapacity;

  /// 访问序 LRU：Dart 的 Map 保持插入顺序，**重插即置后**
  final Map<String, List<String>> _cache = {};

  /// 正在解析的章节（并发合流，避免同一章被重复解析两遍）
  final Map<String, Future<List<String>>> _inflight = {};

  int get cachedCount => _cache.length;

  /// 解析某章的图片地址
  ///
  /// - 命中缓存 → 立即返回；
  /// - [rule] 为空 / 章节地址为空 → 返回空表（调用方据此提示"无法解析"）；
  /// - 解析抛错或结果为空 → 返回空表，**不写缓存**（空结果可能是临时失败，
  ///   写进去会让这一章在本次阅读里永远翻不出来）。
  Future<List<String>> resolve({
    required Rule? rule,
    required MediaEpisode chapter,
    String baseUrl = '',
  }) async {
    final url = chapter.url.trim();
    if (url.isEmpty) return const [];

    // 兜底：章节项直接指向图片（部分图集规则也用 items/groups 承载图片）→ 无需解析
    if (_looksLikeImage(url)) {
      final direct = resolveMediaUrl(url, baseUrl: baseUrl);
      return direct.isEmpty ? const [] : [direct];
    }

    final key = '${rule?.id ?? '-'}|$url';
    final cached = _read(key);
    if (cached != null) return cached;
    if (rule == null) return const [];

    final running = _inflight[key];
    if (running != null) return running;
    _inflight[key] = _parse(rule, chapter, url, baseUrl, key);
    try {
      return await _inflight[key]!;
    } finally {
      _inflight.remove(key);
    }
  }

  /// 静默预取相邻章（失败只记日志，绝不抛出、不阻塞当前阅读）
  ///
  /// 预取的意义只在跨章那一刻：翻到下一章时图片已经在缓存里，直接渲染。
  void prefetchNeighbors({
    required Rule? rule,
    required List<MediaEpisode> chapters,
    required int index,
    String baseUrl = '',
    int radius = 1,
  }) {
    if (rule == null || radius <= 0) return;
    for (var delta = 1; delta <= radius; delta++) {
      for (final target in [index + delta, index - delta]) {
        if (target < 0 || target >= chapters.length) continue;
        unawaited(
          resolve(rule: rule, chapter: chapters[target], baseUrl: baseUrl),
        );
      }
    }
  }

  void clear() {
    _cache.clear();
    _inflight.clear();
  }

  Future<List<String>> _parse(
    Rule rule,
    MediaEpisode chapter,
    String url,
    String baseUrl,
    String key,
  ) async {
    try {
      final result = await _parser(rule, url);
      // 相对图片地址是相对**章节页**的，所以补全基准用章节地址而不是作品地址
      final images = extractImageUrls(result, baseUrl: url);
      if (images.isEmpty) return const [];
      _write(key, images);
      return images;
    } catch (e) {
      debugPrint('[ComicChapterImages] 解析失败(${chapter.title}): $e');
      return const [];
    }
  }

  /// 从 parse 结果里抽取图片地址
  ///
  /// 容忍规则作者的三种常见写法（与 detail 解析同源，但多一层包装容忍度）：
  /// 1. `{ items: ["http...jpg"] }` —— 官方推荐；
  /// 2. `{ images: [...] }` / 直接返回数组；
  /// 3. 数组元素是对象（`{url: …}` / `{src: …}`）。
  static List<String> extractImageUrls(Object? result, {String baseUrl = ''}) {
    final List<dynamic>? raw;
    if (result is Map) {
      final candidate =
          result['items'] ?? result['images'] ?? result['content'];
      raw = candidate is List ? candidate : null;
    } else if (result is List) {
      raw = result;
    } else {
      raw = null;
    }
    if (raw == null) return const [];

    final urls = <String>[];
    final seen = <String>{};
    for (final entry in raw) {
      final value = entry is Map ? (entry['url'] ?? entry['src']) : entry;
      if (value == null) continue;
      final resolved = resolveMediaUrl(value.toString(), baseUrl: baseUrl);
      if (resolved.isEmpty) continue;
      if (seen.add(resolved)) urls.add(resolved);
    }
    return urls;
  }

  List<String>? _read(String key) {
    final value = _cache.remove(key);
    if (value == null) return null;
    _cache[key] = value; // 重插置后 = 刷新使用顺序
    return value;
  }

  void _write(String key, List<String> images) {
    _cache.remove(key);
    _cache[key] = images;
    if (cacheCapacity <= 0) return;
    while (_cache.length > cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
  }

  static final RegExp _imageExtension = RegExp(
    r'\.(jpe?g|png|gif|webp|bmp|avif)(\?|#|$)',
    caseSensitive: false,
  );

  /// 地址本身是否像一张图（仅用于"规则直接给了图片"这一种兜底，不做常规判定）
  static bool _looksLikeImage(String url) => _imageExtension.hasMatch(url);
}
