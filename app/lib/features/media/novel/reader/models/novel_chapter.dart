/// 小说章节模型
///
/// 纯数据（无 Flutter 依赖）。仅被「小说详情页 + 阅读器」使用，
/// 因此留在 `features/media/novel/` 内，未上提到 `domain/`。
class NovelChapter {
  final String title;

  /// 已就绪的正文（为空表示尚未抓取）
  final String content;

  /// 章节正文的远程地址（沙箱按需抓取用）
  final String? url;

  const NovelChapter({required this.title, this.content = '', this.url});

  NovelChapter copyWith({String? title, String? content, String? url}) {
    return NovelChapter(
      title: title ?? this.title,
      content: content ?? this.content,
      url: url ?? this.url,
    );
  }
}
