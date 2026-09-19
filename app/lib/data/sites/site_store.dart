import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fluxforge/core/storage/app_storage.dart';

/// 自定义站点入口模型
///
/// 与「规则源」严格区分：规则源是给解析引擎使用的地址（`Rule.baseUrl`），
/// 站点是用户自己添加、直接用内置浏览器打开的网站入口。
class SiteEntry {
  const SiteEntry({
    required this.id,
    required this.name,
    required this.url,
    required this.createdAt,
  });

  /// 稳定唯一标识（新增时间戳生成，用于编辑 / 删除定位）
  final String id;

  /// 展示名称
  final String name;

  /// 完整地址（已规范化，含 scheme）
  final String url;

  final DateTime createdAt;

  SiteEntry copyWith({String? name, String? url}) {
    return SiteEntry(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SiteEntry.fromJson(Map<String, dynamic> json) {
    return SiteEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// 自定义站点管理服务
///
/// 数据落在 `AppStorage` 的 JSON 字符串中，与收藏 / 历史等本地数据同级；
/// 页面通过 [sitesNotifier] 订阅，增删改后即刻回显。
class SiteStore {
  static const String storageKey = 'custom_sites';

  final ValueNotifier<List<SiteEntry>> sitesNotifier =
      ValueNotifier<List<SiteEntry>>([]);

  List<SiteEntry> get sites => sitesNotifier.value;

  SiteStore() {
    _load();
  }

  /// 补全 scheme 并去除首尾空白（用户输入 `example.com` 也能直接打开）
  static String normalizeUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains('://')) return trimmed;
    return 'https://$trimmed';
  }

  /// 地址是否可打开（仅接受 http / https 且 host 非空）
  static bool isValidUrl(String raw) {
    final normalized = normalizeUrl(raw);
    if (normalized.isEmpty) return false;
    final uri = Uri.tryParse(normalized);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// 新增站点（同地址去重，已存在则更新名称并置顶）
  Future<void> add({required String name, required String url}) async {
    final normalized = normalizeUrl(url);
    final entry = SiteEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? _fallbackName(normalized) : name.trim(),
      url: normalized,
      createdAt: DateTime.now(),
    );

    final list = List<SiteEntry>.from(sites)
      ..removeWhere((e) => e.url == normalized)
      ..insert(0, entry);
    await _save(list);
  }

  /// 编辑站点（名称 / 地址）
  Future<void> update(String id, {required String name, required String url}) async {
    final normalized = normalizeUrl(url);
    final list = sites
        .map((e) => e.id == id
            ? e.copyWith(
                name: name.trim().isEmpty ? _fallbackName(normalized) : name.trim(),
                url: normalized,
              )
            : e)
        .toList();
    await _save(list);
  }

  Future<void> remove(String id) async {
    final list = sites.where((e) => e.id != id).toList();
    await _save(list);
  }

  /// 整体导入（供备份还原调用）
  Future<void> setSites(List<SiteEntry> list) => _save(list);

  Future<void> clear() async {
    sitesNotifier.value = const [];
    await AppStorage.remove(storageKey);
  }

  /// 名称缺省时用域名兜底（如 `example.com`）
  static String _fallbackName(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }

  Future<void> _load() async {
    try {
      final raw = await AppStorage.getString(storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      sitesNotifier.value = List.unmodifiable(
        decoded
            .whereType<Map>()
            .map((e) => SiteEntry.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.url.isNotEmpty)
            .toList(),
      );
    } catch (e) {
      debugPrint('[SiteStore] 加载站点失败: $e');
    }
  }

  Future<void> _save(List<SiteEntry> list) async {
    sitesNotifier.value = List.unmodifiable(list);
    try {
      await AppStorage.setString(
        storageKey,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[SiteStore] 保存站点失败: $e');
    }
  }
}
