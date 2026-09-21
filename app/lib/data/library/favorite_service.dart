import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fluxforge/core/storage/app_storage.dart';

/// 统一多媒体收藏数据项模型
class FavoriteItem {
  final String id; // 媒体唯一标识 (直链URL或唯一ID)
  final String title; // 媒体名称
  final String cover; // 封面海报图
  final String mediaType; // 媒体类型: video / novel / picture / comic
  final String ruleId; // 绑定的规则标识
  final String lastEpisode; // 上次观看/阅读的集数或章节
  final String latestEpisode; // 探测到的源站最新集数或章节
  final bool hasUpdate; // 是否有未读的新更新
  final DateTime updatedAt; // 最近更新时间

  const FavoriteItem({
    required this.id,
    required this.title,
    this.cover = '',
    this.mediaType = 'video',
    this.ruleId = '',
    this.lastEpisode = '',
    this.latestEpisode = '',
    this.hasUpdate = false,
    required this.updatedAt,
  });

  FavoriteItem copyWith({
    String? id,
    String? title,
    String? cover,
    String? mediaType,
    String? ruleId,
    String? lastEpisode,
    String? latestEpisode,
    bool? hasUpdate,
    DateTime? updatedAt,
  }) {
    return FavoriteItem(
      id: id ?? this.id,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      mediaType: mediaType ?? this.mediaType,
      ruleId: ruleId ?? this.ruleId,
      lastEpisode: lastEpisode ?? this.lastEpisode,
      latestEpisode: latestEpisode ?? this.latestEpisode,
      hasUpdate: hasUpdate ?? this.hasUpdate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'cover': cover,
      'mediaType': mediaType,
      'ruleId': ruleId,
      'lastEpisode': lastEpisode,
      'latestEpisode': latestEpisode,
      'hasUpdate': hasUpdate,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未知媒体',
      cover: json['cover']?.toString() ?? '',
      mediaType: json['mediaType']?.toString() ?? 'video',
      ruleId: json['ruleId']?.toString() ?? '',
      lastEpisode: json['lastEpisode']?.toString() ?? '',
      latestEpisode: json['latestEpisode']?.toString() ?? '',
      hasUpdate: json['hasUpdate'] == true,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// 追更探测：访问源站取该收藏项的最新集 / 章（返回 null 表示未知或探测失败）
///
/// 由调用方注入 —— `data/` 层不反向依赖详情抓取链路，与
/// `ChapterContentPipeline(parseRule: …)` 同一「默认实现在外、可注入可测」范式。
typedef FavoriteLatestProbe = Future<String?> Function(FavoriteItem item);

/// 本地真实进度读取（消费记录里的「上次看到」）
///
/// 同样由调用方注入：收藏库自己不掌握播放进度，[FavoriteItem.lastEpisode]
/// 只是导入备份或确实没有进度时的兜底快照。
typedef FavoriteProgressReader = String Function(FavoriteItem item);

/// 统一收藏与智能追更提醒服务
///
/// 管理跨媒体收藏库，支持自动追更比对、更新红点胶囊高亮
class FavoriteService {
  static const String storageKey = 'app_favorites';

  final ValueNotifier<List<FavoriteItem>> favoritesNotifier =
      ValueNotifier<List<FavoriteItem>>([]);

  List<FavoriteItem> get favorites => favoritesNotifier.value;

  bool _isLoaded = false;

  /// 是否已完成首次磁盘加载
  ///
  /// 供页面区分「尚未加载」与「确实没有收藏」—— 否则首帧必然闪一次空态。
  bool get isLoaded => _isLoaded;

  /// 是否有未读更新的红点指示
  bool get hasAnyUpdate => favorites.any((item) => item.hasUpdate);

  FavoriteService() {
    _loadFavorites();
  }

  /// 从持久层加载收藏数据
  Future<void> _loadFavorites() async {
    try {
      final jsonStr = await AppStorage.getString(storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final loaded = decoded
            .map(
              (e) => FavoriteItem.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        favoritesNotifier.value = List.unmodifiable(loaded);
      } else {
        favoritesNotifier.value = [];
      }
    } catch (e) {
      debugPrint('[FavoriteService] 加载收藏数据失败: $e');
      favoritesNotifier.value = [];
    } finally {
      _isLoaded = true;
    }
  }

  /// 持久化保存收藏列表
  Future<void> _saveFavorites(List<FavoriteItem> list) async {
    favoritesNotifier.value = List.unmodifiable(list);
    try {
      final jsonList = list.map((e) => e.toJson()).toList();
      await AppStorage.setString(storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[FavoriteService] 保存收藏失败: $e');
    }
  }

  /// 检查某媒体是否已收藏
  bool isFavorite(String id) {
    return favorites.any((item) => item.id == id);
  }

  /// 添加收藏
  Future<void> addFavorite(FavoriteItem item) async {
    final current = List<FavoriteItem>.from(favorites);
    current.removeWhere((e) => e.id == item.id);
    current.insert(0, item);
    await _saveFavorites(current);
  }

  /// 取消收藏
  Future<void> removeFavorite(String id) async {
    final current = List<FavoriteItem>.from(favorites);
    current.removeWhere((e) => e.id == id);
    await _saveFavorites(current);
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(FavoriteItem item) async {
    if (isFavorite(item.id)) {
      await removeFavorite(item.id);
      return false;
    } else {
      await addFavorite(item);
      return true;
    }
  }

  /// 标记已读（仅消除追更红点）
  ///
  /// **不再改写 [FavoriteItem.lastEpisode]**：那是「上次看到」的展示来源，
  /// 打开详情页并不代表用户看完了新一集，把它改成 `latestEpisode` 属于伪造
  /// 观看进度（并且会污染与消费记录的一致性）。真实进度一律从
  /// [FavoriteProgressReader] 注入读取。
  Future<void> markAsRead(String id) async {
    final current = favorites.map((item) {
      if (item.id == id) return item.copyWith(hasUpdate: false);
      return item;
    }).toList();
    await _saveFavorites(current);
  }

  /// 执行智能追更检测
  ///
  /// 两部分真值都由调用方注入，缺省时退化为「只按本地已存字段比对」：
  /// - [probe]：访问源站取该作品的最新集 / 章（缺省不联网 → 恒无新更新）；
  /// - [progressOf]：本地真实进度（缺省回退 [FavoriteItem.lastEpisode]）。
  ///
  /// 「有更新」的判定是 **源站最新 ≠ 本地真实进度**。原先只比较 `latestEpisode`
  /// 与 `lastEpisode` 两个本地字段，而 `latestEpisode` 全仓没有任何写入者，
  /// 因此恒返回 0 —— 追更实际上从未生效。
  ///
  /// 逐项探测、单项异常不影响其余（失败时保留原有最新值），返回有更新的作品数。
  Future<int> checkUpdates({
    FavoriteLatestProbe? probe,
    FavoriteProgressReader? progressOf,
  }) async {
    if (favorites.isEmpty) return 0;

    int newUpdateCount = 0;
    final next = <FavoriteItem>[];

    for (final item in favorites) {
      var latest = item.latestEpisode;

      if (probe != null) {
        try {
          final probed = await probe(item);
          if (probed != null && probed.isNotEmpty) latest = probed;
        } catch (e) {
          debugPrint('[FavoriteService] 追更探测失败(${item.title}): $e');
        }
      }

      final progress = progressOf?.call(item) ?? item.lastEpisode;
      final hasUpdate = latest.isNotEmpty && latest != progress;
      if (hasUpdate) newUpdateCount++;

      next.add(item.copyWith(latestEpisode: latest, hasUpdate: hasUpdate));
    }

    await _saveFavorites(next);
    return newUpdateCount;
  }

  /// 导入或重置收藏数据 (供备份还原调用)
  Future<void> setFavorites(List<FavoriteItem> list) async {
    await _saveFavorites(list);
  }

  /// 清空所有收藏
  Future<void> clearFavorites() async {
    favoritesNotifier.value = [];
    await AppStorage.remove(storageKey);
  }
}
