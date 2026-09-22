class Rule {
  final dynamic id;
  final String name;
  final String baseUrl;
  final String? description;
  final String type;
  final String code;
  final String? author;
  final String? version;
  final bool enabled;
  final String? createdAt;
  final String? updatedAt;

  Rule({
    this.id,
    required this.name,
    required this.baseUrl,
    this.description,
    required this.type,
    required this.code,
    this.author,
    this.version = '1.0.0',
    this.enabled = true,
    this.createdAt,
    this.updatedAt,
  });

  static List<Rule> fromArray(List<dynamic> list) => list
      .map((item) => Rule.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();

  factory Rule.fromJson(Map<String, dynamic> json) {
    bool isEnabled = true;
    if (json['enabled'] != null) {
      if (json['enabled'] is bool) {
        isEnabled = json['enabled'] as bool;
      } else if (json['enabled'] is num) {
        isEnabled = (json['enabled'] as num) == 1;
      }
    }

    return Rule(
      id: json['id'],
      name: json['name']?.toString() ?? '未命名规则',
      baseUrl: json['baseUrl']?.toString() ?? '',
      description: json['description']?.toString(),
      type: json['type']?.toString() ?? 'video',
      code: json['code']?.toString() ?? '',
      author: json['author']?.toString() ?? 'Admin',
      version: json['version']?.toString() ?? '1.0.0',
      enabled: isEnabled,
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  /// 该规则是否负责解析这个地址
  ///
  /// ### 为什么不是 `baseUrl == url`
  /// 两者不是一个层级：[baseUrl] 是**站点根**（`https://site.com`），
  /// 而 url 是**具体页面**（`https://site.com/manhua/1163.html`）—— 永远不相等。
  /// 真正要判断的是「这个地址属于哪个站」，所以判据落在**域名**上。
  ///
  /// ### 归一化都做了什么
  /// 补 scheme（容忍规则里写 `site.com`）、去 `www.`、统一小写。
  /// 这几步是为了让 `http`/`https`、有无 `www.` 这类**同一站点的书写差异**不会
  /// 被误判成"不匹配"——否则会出现"明明有规则却报未指定规则"。
  ///
  /// 判据是**域名相等**而非字符串包含：既不会因为 host 为空串而命中一切，
  /// 也不会把 `notexample.com` 误判成 `example.com`。
  bool matchesUrl(String url) {
    final base = _hostOf(baseUrl);
    if (base.isEmpty) return false;
    return base == _hostOf(url);
  }

  /// 取站点域名：`https://www.site.com/manga/` → `site.com`
  static String _hostOf(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    if (!value.contains('://')) value = 'https://$value';
    final host = Uri.tryParse(value)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'description': description,
    'type': type,
    'code': code,
    'author': author,
    'version': version,
    'enabled': enabled,
    if (createdAt != null) 'created_at': createdAt,
    if (updatedAt != null) 'updated_at': updatedAt,
  };

  Rule copyWith({
    dynamic id,
    String? name,
    String? baseUrl,
    String? description,
    String? type,
    String? code,
    String? author,
    String? version,
    bool? enabled,
    String? createdAt,
    String? updatedAt,
  }) {
    return Rule(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      description: description ?? this.description,
      type: type ?? this.type,
      code: code ?? this.code,
      author: author ?? this.author,
      version: version ?? this.version,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
