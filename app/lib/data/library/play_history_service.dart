import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:fluxforge/core/storage/app_storage.dart';

/// 跨媒体消费记录模型 (观看/阅读历史 + 断点续播进度)
///
/// 覆盖三大媒体类型：
/// - video：记录播放秒数与总时长，用于「继续观看」与断点秒级续播；
/// - novel / comic：记录章节索引与总章节数，用于「继续阅读」与章节续读。
class PlayRecord {
  /// 媒体唯一标识 (优先采用详情页 URL，兜底 `标题|规则ID` 组合)
  final String id;

  /// 媒体标题
  final String title;

  /// 封面海报
  final String cover;

  /// 媒体类型: video / novel / comic
  final String mediaType;

  /// 绑定的规则标识
  final String ruleId;

  /// 当前进度名称 (如 "第12集" / "第3章")
  final String episodeName;

  /// 当前进度索引 (集数/章节索引，从 0 开始)
  final int episodeIndex;

  /// 总集数/总章节数 (未知为 0)
  final int totalEpisodes;

  /// 视频播放进度 (秒)，小说/漫画恒为 0
  final int positionSeconds;

  /// 视频总时长 (秒)
  final int durationSeconds;

  /// 最近消费时间
  final DateTime updatedAt;

  const PlayRecord({
    required this.id,
    required this.title,
    this.cover = '',
    this.mediaType = 'video',
    this.ruleId = '',
    this.episodeName = '',
    this.episodeIndex = 0,
    this.totalEpisodes = 0,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    required this.updatedAt,
  });

  /// 综合进度百分比 (0.0 ~ 1.0)，供「继续观看」卡片渲染细进度条
  double get progress {
    // 1. 视频优先按播放秒数比例计算
    if (durationSeconds > 0 && positionSeconds > 0) {
      return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
    }
    // 2. 小说/漫画按章节索引比例计算
    if (totalEpisodes > 1) {
      return ((episodeIndex + 1) / totalEpisodes).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  /// 进度副标题文案 (如 "看到 12:45" / "读到 第3章")
  String get progressLabel {
    if (mediaType == 'video') {
      if (positionSeconds > 0) {
        final m = positionSeconds ~/ 60;
        final s = positionSeconds % 60;
        final text = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
        return '看到 $text';
      }
      return '尚未开始';
    }
    if (episodeName.isNotEmpty) return '读到 $episodeName';
    return '尚未开始';
  }

  PlayRecord copyWith({
    String? id,
    String? title,
    String? cover,
    String? mediaType,
    String? ruleId,
    String? episodeName,
    int? episodeIndex,
    int? totalEpisodes,
    int? positionSeconds,
    int? durationSeconds,
    DateTime? updatedAt,
  }) {
    return PlayRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      mediaType: mediaType ?? this.mediaType,
      ruleId: ruleId ?? this.ruleId,
      episodeName: episodeName ?? this.episodeName,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
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
      'episodeName': episodeName,
      'episodeIndex': episodeIndex,
      'totalEpisodes': totalEpisodes,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PlayRecord.fromJson(Map<String, dynamic> json) {
    return PlayRecord(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未知媒体',
      cover: json['cover']?.toString() ?? '',
      mediaType: json['mediaType']?.toString() ?? 'video',
      ruleId: json['ruleId']?.toString() ?? '',
      episodeName: json['episodeName']?.toString() ?? '',
      episodeIndex: (json['episodeIndex'] as num?)?.toInt() ?? 0,
      totalEpisodes: (json['totalEpisodes'] as num?)?.toInt() ?? 0,
      positionSeconds: (json['positionSeconds'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// 统一媒体消费历史与断点续播服务 (PlayHistoryService)
///
/// 设计要点：
/// 1. **高频写入节流**：播放器 `onProgress` 约每 500ms 回调一次，若每次落盘会造成
///    IO 抖动与 UI 狂刷，因此内存即时更新、磁盘按 [_flushInterval] 节流持久化；
/// 2. **去重置顶**：同一媒体重复消费只保留一条最新记录，列表按时间倒序；
/// 3. **容量上限**：最多保留 [maxRecords] 条，超出自动淘汰最旧记录。
class PlayHistoryService {
  static const String storageKey = 'play_history';

  /// 最大记录条数上限
  static const int maxRecords = 200;

  /// 磁盘落盘节流间隔
  static const Duration _flushInterval = Duration(seconds: 5);

  final ValueNotifier<List<PlayRecord>> recordsNotifier =
      ValueNotifier<List<PlayRecord>>([]);

  /// 内部可变缓存 (notifier 对外暴露的是不可变快照)
  final List<PlayRecord> _cache = [];

  /// 上次落盘时间戳
  DateTime _lastFlushAt = DateTime.fromMillisecondsSinceEpoch(0);

  List<PlayRecord> get records => recordsNotifier.value;

  /// 记录总数
  int get totalCount => _cache.length;

  PlayHistoryService() {
    _load();
  }

  /// 异步显式预热初始化
  Future<void> init() async {
    await _load();
  }

  /// 从持久层加载消费历史
  Future<void> _load() async {
    try {
      final jsonStr = await AppStorage.getString(storageKey);
      if (jsonStr == null || jsonStr.isEmpty) return;

      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! List) return;

      _cache
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((e) => PlayRecord.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.id.isNotEmpty),
        );
      _publish();
    } catch (e) {
      debugPrint('[PlayHistoryService] 加载消费历史失败: $e');
    }
  }

  /// 记录或更新一条消费记录 (去重置顶 + 异步落盘)
  Future<void> upsert(PlayRecord record) async {
    if (record.id.isEmpty) return;

    _cache.removeWhere((e) => e.id == record.id);
    _cache.insert(0, record);
    if (_cache.length > maxRecords) {
      _cache.removeRange(maxRecords, _cache.length);
    }
    _publish();
    await _save();
  }

  /// 高频播放/阅读进度更新
  ///
  /// 内存即时生效；磁盘写入按 [PlayHistoryService._flushInterval] 节流，
  /// 同时仅在达到节流窗口时才通知 UI，避免播放过程中「我的」页疯狂重绘。
  void updateProgress({
    required String id,
    String? episodeName,
    int? episodeIndex,
    int? totalEpisodes,
    int? positionSeconds,
    int? durationSeconds,
    bool forceNotify = false,
  }) {
    if (id.isEmpty) return;
    final index = _cache.indexWhere((e) => e.id == id);
    if (index < 0) return; // 未在详情页登记过的媒体不创建幽灵记录

    _cache[index] = _cache[index].copyWith(
      episodeName: episodeName,
      episodeIndex: episodeIndex,
      totalEpisodes: totalEpisodes,
      positionSeconds: positionSeconds,
      durationSeconds: durationSeconds,
      updatedAt: DateTime.now(),
    );

    final now = DateTime.now();
    if (forceNotify || now.difference(_lastFlushAt) >= _flushInterval) {
      _publish();
      _lastFlushAt = now;
      _save();
    }
  }

  /// 查询指定媒体的历史记录 (用于断点续播)
  PlayRecord? getById(String id) {
    for (final record in _cache) {
      if (record.id == id) return record;
    }
    return null;
  }

  /// 最近消费记录 (默认取前 20 条，供「继续观看」横滑流使用)
  List<PlayRecord> recent({int limit = 20}) {
    return _cache.take(limit).toList();
  }

  /// 按媒体类型过滤的消费记录
  List<PlayRecord> byType(String mediaType) {
    return _cache.where((e) => e.mediaType == mediaType).toList();
  }

  /// 移除单条记录
  Future<void> remove(String id) async {
    _cache.removeWhere((e) => e.id == id);
    _publish();
    await _save();
  }

  /// 清空全部消费历史
  Future<void> clear() async {
    _cache.clear();
    _publish();
    await AppStorage.remove(storageKey);
  }

  /// 导入或覆盖消费历史 (供备份还原调用)
  Future<void> setRecords(List<PlayRecord> list) async {
    _cache
      ..clear()
      ..addAll(list.take(maxRecords));
    _publish();
    await _save();
  }

  /// 强制立即落盘 (用于离开播放页等关键时机)
  Future<void> flush() async {
    if (_cache.isEmpty) return;
    _lastFlushAt = DateTime.now();
    await _save();
  }

  /// 发布不可变快照，触发 UI 响应式更新
  void _publish() {
    recordsNotifier.value = List.unmodifiable(List<PlayRecord>.from(_cache));
  }

  /// 持久化到本地存储
  Future<void> _save() async {
    try {
      final jsonList = _cache.map((e) => e.toJson()).toList();
      await AppStorage.setString(storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[PlayHistoryService] 保存消费历史失败: $e');
    }
  }
}
