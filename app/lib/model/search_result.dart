class SearchResult {
  final String title;
  final String? description;
  final String? cover;
  final String? url;
  final String? type;
  final List<String>? tag;
  final String? date;
  final String? baseUrl;
  final Map<String, dynamic>? extra;

  SearchResult({
    required this.title,
    this.description,
    this.cover,
    this.url,
    this.type,
    this.tag,
    this.date,
    this.baseUrl,
    this.extra,
  });

  /// 兼容旧代码对 path 的访问
  String get path => url ?? '';

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    List<String>? parsedTags;
    if (json['tag'] != null) {
      if (json['tag'] is List) {
        parsedTags = (json['tag'] as List).map((e) => e.toString()).toList();
      } else if (json['tag'] is String) {
        parsedTags = [json['tag'].toString()];
      }
    } else if (json['tags'] != null) {
      if (json['tags'] is List) {
        parsedTags = (json['tags'] as List).map((e) => e.toString()).toList();
      }
    }

    return SearchResult(
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      cover: json['cover']?.toString(),
      url: json['url']?.toString() ?? json['path']?.toString(),
      type: json['type']?.toString(),
      tag: parsedTags,
      date: json['date']?.toString(),
      baseUrl: json['baseUrl']?.toString() ?? json['base_url']?.toString(),
      extra: json['extra'] != null ? Map<String, dynamic>.from(json['extra'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    if (description != null) 'description': description,
    if (cover != null) 'cover': cover,
    if (url != null) 'url': url,
    if (type != null) 'type': type,
    if (tag != null) 'tag': tag,
    if (date != null) 'date': date,
    if (baseUrl != null) 'baseUrl': baseUrl,
    if (extra != null) 'extra': extra,
  };

  static List<SearchResult> fromArray(List<dynamic> list) =>
      list.map((item) => SearchResult.fromJson(Map<String, dynamic>.from(item as Map))).toList();
}