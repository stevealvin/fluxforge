class Episode {
  final String name;
  final String url;
  final String? playUrl;

  Episode({
    required this.name,
    required this.url,
    this.playUrl,
  });

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
    name: json['title']?.toString() ?? json['name']?.toString() ?? '默认集',
    url: json['url']?.toString() ?? '',
    playUrl: json['playUrl']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    if (playUrl != null) 'playUrl': playUrl,
  };
}

class PlaySource {
  final String sourceName;
  final List<Episode> episodes;

  PlaySource({
    required this.sourceName,
    required this.episodes,
  });

  factory PlaySource.fromJson(Map<String, dynamic> json) => PlaySource(
    sourceName: json['name']?.toString() ?? '默认线路',
    episodes: (json['items'] as List<dynamic>?)
            ?.map((e) => Episode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'sourceName': sourceName,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
}

class DetailResult {
  /// 标题
  final String title;
  /// 类型（movie / tv / photo / picture / manga / novel / other）
  final String type;
  /// 封面图
  final String cover;
  /// 描述 / 简介
  final String? description;
  /// 作者 / 导演
  final String? author;
  /// 连载状态
  final String? status;
  /// 分类标签
  final List<String>? tags;
  /// 详情页 URL
  final String url;
  /// 选集列表（影视/动画）
  final List<Episode>? episodes;
  /// 多播放线路（可选）
  final List<PlaySource>? sources;
  /// 图片列表（图集/漫画）
  final List<String>? images;
  /// 剧照 / 截图 / 插图预览流
  final List<String>? previews;
  /// 相似作品 / 相关推荐
  final List<Map<String, dynamic>>? related;
  /// 可选额外信息
  final Map<String, dynamic>? extra;

  DetailResult({
    required this.title,
    required this.type,
    required this.cover,
    this.description,
    this.author,
    this.status,
    this.tags,
    required this.url,
    this.episodes,
    this.sources,
    this.images,
    this.previews,
    this.related,
    this.extra,
  });

  factory DetailResult.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type']?.toString() ?? 'video').toLowerCase();
    final rawItems = json['items'] as List<dynamic>?;

    List<Episode>? parsedEpisodes;
    if (rawItems != null &&
        typeStr != 'photo' &&
        typeStr != 'picture' &&
        typeStr != 'image' &&
        typeStr != 'gallery') {
      parsedEpisodes = rawItems
          .map((e) {
            if (e is Map) {
              final map = Map<String, dynamic>.from(e);
              return Episode.fromJson(map);
            } else {
              return Episode(name: '集数', url: e.toString());
            }
          })
          .toList();
    }

    List<PlaySource>? parsedSources;
    final rawSources = json['groups'] as List<dynamic>?;
    if (rawSources != null) {
      parsedSources = rawSources
          .map((s) => PlaySource.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
    }

    List<String>? parsedImages;
    if (rawItems != null &&
        (typeStr == 'photo' || typeStr == 'picture' || typeStr == 'image' || typeStr == 'gallery')) {
      parsedImages = rawItems
          .map((i) {
            if (i is Map) {
              return (i['url'] ?? '').toString();
            }
            return i.toString();
          })
          .where((s) => s.isNotEmpty)
          .toList();
    }

    List<String>? parsedPreviews;
    if (json['previews'] is List) {
      parsedPreviews = (json['previews'] as List<dynamic>)
          .map((p) => p.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    List<Map<String, dynamic>>? parsedRelated;
    if (json['related'] is List) {
      parsedRelated = (json['related'] as List<dynamic>)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    List<String>? parsedTags;
    if (json['tags'] != null) {
      parsedTags = (json['tags'] as List<dynamic>).map((t) => t.toString()).toList();
    }

    return DetailResult(
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? 'video',
      cover: json['cover']?.toString() ?? '',
      description: json['description']?.toString(),
      author: json['author']?.toString(),
      status: json['status']?.toString(),
      tags: parsedTags,
      url: json['url']?.toString() ?? '',
      episodes: parsedEpisodes,
      sources: parsedSources,
      images: parsedImages,
      previews: parsedPreviews,
      related: parsedRelated,
      extra: json['extra'] != null ? Map<String, dynamic>.from(json['extra'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'type': type,
    'cover': cover,
    if (description != null) 'description': description,
    if (author != null) 'author': author,
    if (status != null) 'status': status,
    if (tags != null) 'tags': tags,
    'url': url,
    if (episodes != null) 'episodes': episodes!.map((e) => e.toJson()).toList(),
    if (sources != null) 'sources': sources!.map((s) => s.toJson()).toList(),
    if (images != null) 'images': images,
    if (previews != null) 'previews': previews,
    if (related != null) 'related': related,
    if (extra != null) 'extra': extra,
  };
}
