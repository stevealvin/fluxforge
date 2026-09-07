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
    name: json['name']?.toString() ?? '默认集',
    url: json['url']?.toString() ?? '',
    playUrl: json['playUrl']?.toString() ?? json['play_url']?.toString(),
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
    sourceName: json['sourceName']?.toString() ?? json['name']?.toString() ?? '默认线路',
    episodes: (json['episodes'] as List<dynamic>?)
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
    this.extra,
  });

  /// 兼容旧版 contentUrls 读取
  List<String> get contentUrls {
    if (images != null && images!.isNotEmpty) return images!;
    if (episodes != null && episodes!.isNotEmpty) {
      return episodes!.map((e) => e.playUrl ?? e.url).toList();
    }
    return [];
  }

  /// 兼容旧版 path 读取
  String get path => url;

  factory DetailResult.fromJson(Map<String, dynamic> json) {
    List<Episode>? parsedEpisodes;
    if (json['episodes'] != null) {
      parsedEpisodes = (json['episodes'] as List<dynamic>)
          .map((e) {
            if (e is Map) {
              return Episode.fromJson(Map<String, dynamic>.from(e));
            } else {
              return Episode(name: '集数', url: e.toString());
            }
          })
          .toList();
    } else if (json['contentUrls'] != null) {
      parsedEpisodes = (json['contentUrls'] as List<dynamic>)
          .map((e) => Episode(name: '播放源', url: e.toString()))
          .toList();
    }

    List<PlaySource>? parsedSources;
    if (json['sources'] != null) {
      parsedSources = (json['sources'] as List<dynamic>)
          .map((s) => PlaySource.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
    }

    List<String>? parsedImages;
    if (json['images'] != null) {
      parsedImages = (json['images'] as List<dynamic>).map((i) => i.toString()).toList();
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
      url: json['url']?.toString() ?? json['path']?.toString() ?? '',
      episodes: parsedEpisodes,
      sources: parsedSources,
      images: parsedImages,
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
    if (extra != null) 'extra': extra,
  };
}
