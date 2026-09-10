class Episode {
  final String title;
  final String url;
  final String? desc;
  final String? playUrl;

  Episode({
    required this.title,
    required this.url,
    this.desc,
    this.playUrl,
  });

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
    title: json['title']?.toString() ?? '',
    url: json['url']?.toString() ?? '',
    desc: json['desc']?.toString(),
    playUrl: json['playUrl']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    if (desc != null) 'desc': desc,
    if (playUrl != null) 'playUrl': playUrl,
  };
}

class PlaySource {
  final String name;
  final List<Episode> items;

  PlaySource({
    required this.name,
    required this.items,
  });

  factory PlaySource.fromJson(Map<String, dynamic> json) => PlaySource(
    name: json['name']?.toString() ?? '',
    items: (json['items'] as List<dynamic>?)
            ?.map((e) => Episode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'items': items.map((e) => e.toJson()).toList(),
  };
}

class DetailResult {
  /// 标题
  final String title;
  /// 类型（video / picture / novel）
  final String type;
  /// 封面图
  final String cover;
  /// 描述 / 简介
  final String? desc;
  /// 作者 / 导演
  final String? author;
  /// 评分
  final String? rating;
  /// 分类标签
  final List<String>? tags;
  /// 详情页 URL
  final String url;
  /// 核心选集/子资源列表
  final List<dynamic>? items;
  /// 多播放线路 / 分卷分组
  final List<PlaySource>? groups;
  /// 剧照 / 截图 / 插图预览流
  final List<String>? previews;
  /// 相似作品 / 相关推荐
  final List<Map<String, dynamic>>? related;
  /// 视频播放直链
  final String? playUrl;
  /// 文章/小说正文
  final String? content;
  /// 请求头
  final Map<String, String>? headers;
  /// 可选额外信息
  final Map<String, dynamic>? extra;

  DetailResult({
    required this.title,
    required this.type,
    required this.cover,
    this.desc,
    this.author,
    this.rating,
    this.tags,
    required this.url,
    this.items,
    this.groups,
    this.previews,
    this.related,
    this.playUrl,
    this.content,
    this.headers,
    this.extra,
  });

  factory DetailResult.fromJson(Map<String, dynamic> json) {
    List<PlaySource>? parsedGroups;
    final rawGroups = json['groups'] as List<dynamic>?;
    if (rawGroups != null) {
      parsedGroups = rawGroups
          .map((s) => PlaySource.fromJson(Map<String, dynamic>.from(s as Map)))
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
    if (json['tags'] is List) {
      parsedTags = (json['tags'] as List<dynamic>).map((t) => t.toString()).toList();
    }

    Map<String, String>? parsedHeaders;
    if (json['headers'] is Map) {
      parsedHeaders = Map<String, String>.from(
        (json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
      );
    }

    return DetailResult(
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? 'video',
      cover: json['cover']?.toString() ?? '',
      desc: json['desc']?.toString(),
      author: json['author']?.toString(),
      rating: json['rating']?.toString(),
      tags: parsedTags,
      url: json['url']?.toString() ?? '',
      items: json['items'] as List<dynamic>?,
      groups: parsedGroups,
      previews: parsedPreviews,
      related: parsedRelated,
      playUrl: json['playUrl']?.toString(),
      content: json['content']?.toString(),
      headers: parsedHeaders,
      extra: json['extra'] is Map ? Map<String, dynamic>.from(json['extra'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'type': type,
    'cover': cover,
    if (desc != null) 'desc': desc,
    if (author != null) 'author': author,
    if (rating != null) 'rating': rating,
    if (tags != null) 'tags': tags,
    'url': url,
    if (items != null) 'items': items,
    if (groups != null) 'groups': groups!.map((s) => s.toJson()).toList(),
    if (previews != null) 'previews': previews,
    if (related != null) 'related': related,
    if (playUrl != null) 'playUrl': playUrl,
    if (content != null) 'content': content,
    if (headers != null) 'headers': headers,
    if (extra != null) 'extra': extra,
  };
}
