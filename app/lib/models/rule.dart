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

  static List<Rule> fromArray(List<dynamic> list) =>
      list.map((item) => Rule.fromJson(Map<String, dynamic>.from(item as Map))).toList();

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