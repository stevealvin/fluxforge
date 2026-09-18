import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';

/// 章节正文内存缓存（会话级 · 阅读期加速层）
///
/// **定位澄清**：本缓存只写内存、退出阅读器即释放，与「离线下载」（沙盒持久化、
/// 断网可读）是两层不同机制：
/// - 命中缓存 → 切章零等待，但下次进入阅读器就没了；
/// - 需要长期留存请走「跳章自动下载」或详情页「全本下载」。
///
/// **淘汰策略**：访问序 LRU —— 读取即刷新使用顺序，条目数超出 [capacity] 时
/// 优先淘汰最久未使用的章节。淘汰必须传入 [evictOverflow] 的 `protect` 集合：
/// 纵向长卷正在渲染的章节、当前章、预取 / 下载中的章节一旦被淘汰，
/// 会出现空白块或进度计算失真。
class ChapterCache {
  ChapterCache({this.capacity = defaultCapacity});

  /// 默认容量上限
  ///
  /// 按「单章正文约 6 KB（Dart String 为 UTF-16）」估算，200 章约 1.2 MB ——
  /// 足以覆盖纵向长卷的邻近窗口，又能在极长会话中兜住内存增长。
  static const int defaultCapacity = 200;

  /// 容量上限（`<= 0` 表示不限制）
  final int capacity;

  /// 访问序表：Dart 的 Map 保持插入顺序，**重插即置后**，
  /// 因此迭代顺序天然是「最久未使用 → 最近使用」。
  final Map<int, String> _entries = {};

  /// 当前条目数（含空正文占位）
  int get length => _entries.length;

  /// 有效条目数（正文非空）
  int get nonEmptyCount => _entries.values.where((v) => v.isNotEmpty).length;

  bool containsKey(int index) => _entries.containsKey(index);

  /// 读取缓存（命中即刷新其使用顺序）
  String? operator [](int index) {
    final value = _entries.remove(index);
    if (value == null) return null;
    _entries[index] = value;
    return value;
  }

  /// 写入 / 覆盖缓存
  void operator []=(int index, String content) {
    _entries.remove(index);
    _entries[index] = content;
  }

  void remove(int index) => _entries.remove(index);

  void clear() => _entries.clear();

  /// 把章节模型中自带的正文种入缓存（初始化时调用）
  void seedFromChapters(List<NovelChapter> chapters) {
    for (int i = 0; i < chapters.length; i++) {
      final content = chapters[i].content;
      if (content.isNotEmpty) this[i] = content;
    }
  }

  /// 淘汰超出容量的最久未使用条目
  ///
  /// - [protect] 内的索引**永不淘汰**；
  /// - 返回被淘汰的索引集合，调用方据此同步清理章节模型中的正文引用
  ///   （否则 String 仍被 `NovelChapter` 持有，内存不会真正释放）。
  Set<int> evictOverflow({Set<int> protect = const {}}) {
    if (capacity <= 0) return const <int>{};
    if (_entries.length <= capacity) return const <int>{};

    final evicted = <int>{};
    for (final index in _entries.keys.toList(growable: false)) {
      if (_entries.length <= capacity) break;
      // 受保护章节即使超容也不淘汰：宁可暂时超出，也不能让正在阅读的内容出错
      if (protect.contains(index)) continue;
      _entries.remove(index);
      evicted.add(index);
    }
    return evicted;
  }
}
