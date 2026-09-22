import 'package:fluxforge/domain/rule/rule.dart';

/// 媒体业务类型定义 (影视视频/画廊漫画/小说文学)
enum MediaType {
  video('video', '影视视频'),
  comic('comic', '画廊漫画'),
  novel('novel', '小说文学'),
  unknown('unknown', '未知媒介');

  final String value;
  final String label;
  const MediaType(this.value, this.label);

  static MediaType fromString(String? type) {
    if (type == null) return MediaType.unknown;
    final lower = type.toLowerCase().trim();
    if (['video', 'tv', 'movie', 'anime', 'film'].contains(lower)) {
      return MediaType.video;
    }
    if (['comic', 'manga', 'image', 'picture', 'photo', 'gallery'].contains(lower)) {
      return MediaType.comic;
    }
    if (['novel', 'book', 'text', 'story'].contains(lower)) {
      return MediaType.novel;
    }
    return MediaType.unknown;
  }
}

/// 图片类作品的内容形态
///
/// **由 detail 返回的元素类型推断，规则无需额外声明任何字段**：
///
/// | 规则返回 | 推断结果 | 含义 |
/// |---|---|---|
/// | `items: ["http...jpg"]` | [images] | 图集：整本书的图片已在 detail 里给全，不需要再解析 |
/// | `items: [{title, url}]` | [chapters] | 漫画：只给了**章节页地址**，每章要再 parse 一层 |
/// | `groups: [{name, items:[{...}]}]` | [chapters] | 同上（多分组形态） |
///
/// 判据与详情解析严格同源：`items` 里的**字符串**只会落进 `imageList`，
/// 而**对象**只会落进 `chapters`，因此两个列表谁非空即代表形态。
enum MediaContentShape {
  /// detail 直接给出图片（图集）
  images,

  /// detail 给出章节表，每章需再解析一层才得到图片（漫画）
  chapters,

  /// 既没有图片也没有章节
  none,
}

/// 选集/分集/章节单项数据模型
class MediaEpisode {
  final String title;
  final String url;
  final String? cover;
  final Map<String, dynamic> extra;

  const MediaEpisode({
    required this.title,
    required this.url,
    this.cover,
    this.extra = const {},
  });

  factory MediaEpisode.fromMap(Map<String, dynamic> map, {int fallbackIndex = 1}) {
    return MediaEpisode(
      title: map['title']?.toString() ?? map['name']?.toString() ?? '第 $fallbackIndex 话',
      url: map['url']?.toString() ?? map['link']?.toString() ?? '',
      cover: map['cover']?.toString() ?? map['thumb']?.toString(),
      extra: map,
    );
  }
}

/// 选集分组/播放线路模型 (例如: '蓝光主线', '超清备用', '单行本', '番外篇')
class MediaGroup {
  final String name;
  final List<MediaEpisode> items;

  const MediaGroup({
    required this.name,
    required this.items,
  });

  factory MediaGroup.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List? ?? [];
    final items = <MediaEpisode>[];
    for (int i = 0; i < rawItems.length; i++) {
      final it = rawItems[i];
      if (it is Map) {
        items.add(MediaEpisode.fromMap(Map<String, dynamic>.from(it), fallbackIndex: i + 1));
      } else if (it is String) {
        items.add(MediaEpisode(title: '第 ${i + 1} 话', url: it));
      }
    }
    return MediaGroup(
      name: map['name']?.toString() ?? '默认分组',
      items: items,
    );
  }
}

/// 相关推荐单项模型
class MediaRelatedItem {
  final String title;
  final String url;
  final String cover;
  final String? desc;
  final String? rating;
  final String? status;
  final String? badge;
  final String? type;
  final Rule? rule;

  const MediaRelatedItem({
    required this.title,
    required this.url,
    required this.cover,
    this.desc,
    this.rating,
    this.status,
    this.badge,
    this.type,
    this.rule,
  });

  factory MediaRelatedItem.fromMap(Map<String, dynamic> map, {Rule? rule}) {
    return MediaRelatedItem(
      title: map['title']?.toString() ?? '未命名推荐',
      url: map['url']?.toString() ?? map['link']?.toString() ?? '',
      cover: map['cover']?.toString() ?? map['thumb']?.toString() ?? map['img']?.toString() ?? '',
      desc: map['desc']?.toString() ?? map['description']?.toString(),
      rating: map['rating']?.toString() ?? map['score']?.toString(),
      status: map['status']?.toString(),
      badge: map['badge']?.toString() ?? map['status']?.toString() ?? map['rating']?.toString(),
      type: map['type']?.toString(),
      rule: rule,
    );
  }
}

/// 媒体详情统一结构化契约模型 (对接沙箱 parseDetail 返回结果)
class MediaDetailData {
  // 通用基础元数据
  final String title;
  final String url;
  final String cover;
  final String? desc;
  final String? author;
  final String? rating;
  final String? updateTime;
  final List<String> tags;
  final Map<String, String> customHeaders;

  // 识别出的媒介业务类型
  final MediaType mediaType;

  // 核心子资源条目 (契约全链路统一标准: 视频选集、小说章节、漫画图集等)
  final List<MediaEpisode> items;

  // 视频业务特有数据
  final String? playUrl;
  final List<MediaGroup> videoGroups;

  // 漫画/图集业务特有数据
  final List<String> imageList;
  final List<MediaGroup> comicGroups;

  // 小说业务特有数据
  final String? textContent;
  final List<MediaEpisode> chapters;

  // 扩展展示 (剧照预览图与相关推荐)
  final List<String> previews;
  final List<MediaRelatedItem> related;

  const MediaDetailData({
    required this.title,
    required this.url,
    required this.cover,
    this.desc,
    this.author,
    this.rating,
    this.updateTime,
    this.tags = const [],
    this.customHeaders = const {},
    this.mediaType = MediaType.unknown,
    this.items = const [],
    this.playUrl,
    this.videoGroups = const [],
    this.imageList = const [],
    this.comicGroups = const [],
    this.textContent,
    this.chapters = const [],
    this.previews = const [],
    this.related = const [],
  });

  bool get isEmpty => title.isEmpty && url.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// 图片类作品的内容形态（元素类型推断，见 [MediaContentShape]）
  ///
  /// 判定顺序即优先级：`groups` → `imageList` → `chapters`。
  /// 注意图集形态下 `chapters` 同样非空（解析时每张图也生成了一条条目），
  /// 所以 `imageList` 必须排在它前面。
  MediaContentShape get contentShape {
    if (comicGroups.any((g) => g.items.isNotEmpty)) {
      return MediaContentShape.chapters;
    }
    if (imageList.isNotEmpty) return MediaContentShape.images;
    if (chapters.isNotEmpty) return MediaContentShape.chapters;
    return MediaContentShape.none;
  }

  /// 是否属于"章节形态"——即必须再解析一层才能拿到图片
  bool get needsChapterParse => contentShape == MediaContentShape.chapters;

  /// 章节形态下的**可读章表**
  ///
  /// 把规则的两种写法统一起来，UI 只需要读它：
  /// - `groups: [...]` → 原样返回（多分组）；
  /// - `items: [{title, url}]` → 合成单一分组（规则两种写法在此归一，
  ///   调用方只需读这一个入口）。
  List<MediaGroup> get readableComicGroups {
    if (comicGroups.isNotEmpty) return comicGroups;
    if (contentShape == MediaContentShape.chapters && chapters.isNotEmpty) {
      return [MediaGroup(name: '章节列表', items: chapters)];
    }
    return const [];
  }

  MediaDetailData copyWith({
    String? title,
    String? url,
    String? cover,
    String? desc,
    String? author,
    String? rating,
    String? updateTime,
    List<String>? tags,
    Map<String, String>? customHeaders,
    MediaType? mediaType,
    List<MediaEpisode>? items,
    String? playUrl,
    List<MediaGroup>? videoGroups,
    List<String>? imageList,
    List<MediaGroup>? comicGroups,
    String? textContent,
    List<MediaEpisode>? chapters,
    List<String>? previews,
    List<MediaRelatedItem>? related,
  }) {
    return MediaDetailData(
      title: title ?? this.title,
      url: url ?? this.url,
      cover: cover ?? this.cover,
      desc: desc ?? this.desc,
      author: author ?? this.author,
      rating: rating ?? this.rating,
      updateTime: updateTime ?? this.updateTime,
      tags: tags ?? this.tags,
      customHeaders: customHeaders ?? this.customHeaders,
      mediaType: mediaType ?? this.mediaType,
      items: items ?? this.items,
      playUrl: playUrl ?? this.playUrl,
      videoGroups: videoGroups ?? this.videoGroups,
      imageList: imageList ?? this.imageList,
      comicGroups: comicGroups ?? this.comicGroups,
      textContent: textContent ?? this.textContent,
      chapters: chapters ?? this.chapters,
      previews: previews ?? this.previews,
      related: related ?? this.related,
    );
  }
}
