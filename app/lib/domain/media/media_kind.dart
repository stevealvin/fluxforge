/// 媒体类型分组：全仓统一的「影视 / 小说 / 漫画·图集」三分法
///
/// ### 为什么放在 domain 层
/// 「规则类型 → 媒体类型」的判定被三处用到：搜索结果排版、规则目录卡片、发现页网格。
/// 它们分属三个不同 feature，而架构约定 **feature 之间不得互相依赖**，
/// 因此这份判定必须落在共享的 domain 层，否则只能各写一份、日后口径必然漂移
/// （此前正是三处各写了一遍 `isVideoRule`）。
///
/// 判定依据是 `Rule.type`（规则自带标注），大小写与首尾空白均做归一化。
library;

/// 影视类规则的类型标识
const Set<String> kVideoRuleTypes = {'video', 'tv', 'movie', 'anime', 'short'};

/// 小说类规则的类型标识
const Set<String> kNovelRuleTypes = {'novel', 'book', 'txt'};

/// 漫画 / 图集类规则的类型标识
const Set<String> kComicRuleTypes = {
  'comic',
  'manga',
  'picture',
  'gallery',
  'photo',
};

/// 媒体类型分组
///
/// [all] 只用于筛选 UI，不对应任何真实规则类型；其余三档与收藏页、
/// 历史中心的筛选口径保持一致（同一份数据在不同页面不能有两种分法）。
enum MediaKind {
  /// 全部（不筛选）
  all,

  /// 影视（含未标注类型的源，见 [mediaKindOfRuleType] 的兜底说明）
  video,

  /// 小说
  novel,

  /// 漫画 / 图集
  comic,
}

/// 归一化规则类型：小写 + 去首尾空白
String normalizeRuleType(String type) => type.toLowerCase().trim();

/// 该规则类型是否属于影视类
///
/// **空类型视为影视**：未标注类型的源占多数，且它们绝大多数是影视站 ——
/// 这与既有的排版口径完全一致，避免同一条规则在「排版」与「筛选」两处
/// 得到相反结论（那会让筛选出的结果排版错乱）。
bool isVideoRuleType(String type) {
  final normalized = normalizeRuleType(type);
  return normalized.isEmpty || kVideoRuleTypes.contains(normalized);
}

/// 把规则类型映射到媒体类型分组
///
/// 未知类型按影视兜底（与 [isVideoRuleType] 同口径），而不是丢弃 ——
/// 丢掉会让「全部」与各分档的源数对不上，用户会以为源凭空少了。
MediaKind mediaKindOfRuleType(String type) {
  final normalized = normalizeRuleType(type);
  if (normalized.isEmpty || kVideoRuleTypes.contains(normalized)) {
    return MediaKind.video;
  }
  if (kNovelRuleTypes.contains(normalized)) return MediaKind.novel;
  if (kComicRuleTypes.contains(normalized)) return MediaKind.comic;
  return MediaKind.video;
}

/// 分组的显示名（筛选胶囊文案）
extension MediaKindLabel on MediaKind {
  String get label => switch (this) {
    MediaKind.all => '全部',
    MediaKind.video => '影视',
    MediaKind.novel => '小说',
    MediaKind.comic => '漫画·图集',
  };
}
