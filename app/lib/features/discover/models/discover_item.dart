import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/domain/rule/rule.dart';

/// 发现页的聚合条目（跨源）
///
/// 与搜索结果的 `NormalizedSearchResult` 刻意分成两个模型：本条目额外携带
/// [source]（决定海报比例与来源角标）与 [kind]（决定它落在哪个频道）——
/// 这两项是「发现」相对「搜索」的固有差异，而搜索结果并不需要它们。
class DiscoverItem {
  const DiscoverItem({
    required this.title,
    required this.url,
    required this.cover,
    required this.desc,
    required this.badge,
    required this.source,
    required this.kind,
  });

  final String title;
  final String url;
  final String cover;
  final String desc;
  final String? badge;

  /// 条目所属的规则源
  final Rule source;

  /// 归一化后的媒体类型分组（决定它落在哪个频道）
  final MediaKind kind;

  /// 跨源去重键：标题归一化（去空白、忽略大小写）
  String get dedupeKey => normalizeTitle(title);

  /// 信息完整度打分 —— 去重时保留分高的那条
  ///
  /// 权重体现「用户能看到的价值」：封面 > 描述 > 角标 > 链接。
  int get completenessScore {
    var score = 0;
    if (cover.isNotEmpty) score += 4;
    if (desc.isNotEmpty) score += 2;
    if (badge != null && badge!.isNotEmpty) score += 1;
    if (url.isNotEmpty) score += 1;
    return score;
  }

  /// 标题归一化：去掉所有空白、忽略大小写
  ///
  /// 不同源的标题常有「星海拾遗」与「星 海 拾 遗」这类排版差异，
  /// 不归一化就会在聚合流里出现两条几乎一样的卡片。
  static String normalizeTitle(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.trim().toLowerCase().runes) {
      if (rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D) continue;
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }
}
