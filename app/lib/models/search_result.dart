class SearchResult {
  final String url;
  final String title;
  final String? cover;
  final String? badge;
  final String? desc;
  final String? date;
  final List<String>? tags;
  final Map<String, dynamic>? extra;

  SearchResult({
    required this.url,
    required this.title,
    this.cover,
    this.badge,
    this.desc,
    this.date,
    this.tags,
    this.extra,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    List<String>? parsedTags;
    if (json['tags'] is List) {
      parsedTags = (json['tags'] as List).map((e) => e.toString()).toList();
    }

    return SearchResult(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString(),
      badge: json['badge']?.toString(),
      desc: json['desc']?.toString(),
      date: json['date']?.toString(),
      tags: parsedTags,
      extra: json['extra'] is Map ? Map<String, dynamic>.from(json['extra'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'title': title,
    if (cover != null) 'cover': cover,
    if (badge != null) 'badge': badge,
    if (desc != null) 'desc': desc,
    if (date != null) 'date': date,
    if (tags != null) 'tags': tags,
    if (extra != null) 'extra': extra,
  };

  static List<SearchResult> fromArray(List<dynamic> list) =>
      list.map((item) => SearchResult.fromJson(Map<String, dynamic>.from(item as Map))).toList();
}