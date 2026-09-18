/// 小说正文清洗与规范化工具
///
/// 被小说阅读器（实时抓取展示）与离线下载服务（落盘前清洗）共同复用，
/// 保证「在线阅读」与「离线下载」得到的正文排版完全一致。
library;

/// 智能清洗与规范化小说正文排版
///
/// - 去除 HTML 标签（`<br>` 转行、`</p>` 转段落、其余标签直接剥离）；
/// - 还原常用 HTML 实体字符；
/// - 过滤空白行，并自动补齐两格全角空格的标准首行缩进。
String cleanNovelContent(String raw) {
  if (raw.isEmpty) return '';

  final String text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');

  final lines = text.split('\n');
  final formattedLines = <String>[];
  for (final l in lines) {
    final trimmed = l.trim();
    if (trimmed.isEmpty) continue;
    // 自动补齐两格全角空格标准首行缩进
    if (!trimmed.startsWith('　　')) {
      formattedLines.add('　　$trimmed');
    } else {
      formattedLines.add(trimmed);
    }
  }
  return formattedLines.join('\n\n');
}
