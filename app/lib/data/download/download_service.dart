// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fluxforge/core/network/api_client.dart';
import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/domain/text/novel_text.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/data/rule/rule_service.dart';

/// 离线下载任务状态
enum DownloadStatus {
  pending('排队中'),
  running('下载中'),
  paused('已暂停'),
  completed('已完成'),
  failed('部分失败');

  const DownloadStatus(this.label);
  final String label;
}

/// 离线下载任务模型（小说全本 / 漫画整部）
///
/// 存储位置：App 沙盒文档目录 `fluxforge_offline/`
/// - 小说正文：`novels/<书籍ID>/<章节索引>.txt`
/// - 漫画图片：`comics/<书籍ID>/<URL 稳定哈希>.<扩展名>`
class DownloadTask {
  /// 书籍唯一标识（详情页 URL，兜底标题）
  final String id;
  final String title;
  final String cover;

  /// 媒体类型：novel / comic
  final String mediaType;

  /// 绑定的规则标识（下载时用于调度沙箱）
  final String ruleId;

  /// 详情页源地址
  final String sourceUrl;

  /// 待下载目标地址列表（小说=章节 URL，漫画=图片 URL）
  final List<String> targetUrls;

  /// 目标名称列表（与 [targetUrls] 下标对齐，用于展示）
  final List<String> targetTitles;

  /// 下载图片时透传的防盗链请求头
  final Map<String, String> headers;

  /// 已完成的下标集合
  final Set<int> completed;

  /// 失败的下标集合（不自动重试，避免死循环，由用户手动「重试失败」）
  final Set<int> failed;

  final DownloadStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DownloadTask({
    required this.id,
    required this.title,
    this.cover = '',
    this.mediaType = 'novel',
    this.ruleId = '',
    this.sourceUrl = '',
    this.targetUrls = const [],
    this.targetTitles = const [],
    this.headers = const {},
    this.completed = const {},
    this.failed = const {},
    this.status = DownloadStatus.pending,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 目标总数
  int get total => targetUrls.length;

  /// 已完成数量
  int get doneCount => completed.length;

  /// 下载进度（0.0 ~ 1.0）
  double get progress => total == 0 ? 0.0 : (doneCount / total).clamp(0.0, 1.0);

  /// 是否处于可继续调度状态
  bool get isActive =>
      status == DownloadStatus.pending || status == DownloadStatus.running;

  /// 是否全部完成
  bool get isFinished => status == DownloadStatus.completed;

  /// 进度文案
  String get progressLabel => '$doneCount / $total';

  DownloadTask copyWith({
    String? title,
    String? cover,
    String? ruleId,
    List<String>? targetUrls,
    List<String>? targetTitles,
    Map<String, String>? headers,
    Set<int>? completed,
    Set<int>? failed,
    DownloadStatus? status,
    DateTime? updatedAt,
  }) {
    return DownloadTask(
      id: id,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      mediaType: mediaType,
      ruleId: ruleId ?? this.ruleId,
      sourceUrl: sourceUrl,
      targetUrls: targetUrls ?? this.targetUrls,
      targetTitles: targetTitles ?? this.targetTitles,
      headers: headers ?? this.headers,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      status: status ?? this.status,
      createdAt: createdAt,
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
      'sourceUrl': sourceUrl,
      'targetUrls': targetUrls,
      'targetTitles': targetTitles,
      'headers': headers,
      'completed': completed.toList(),
      'failed': failed.toList(),
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未知作品',
      cover: json['cover']?.toString() ?? '',
      mediaType: json['mediaType']?.toString() ?? 'novel',
      ruleId: json['ruleId']?.toString() ?? '',
      sourceUrl: json['sourceUrl']?.toString() ?? '',
      targetUrls: (json['targetUrls'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      targetTitles: (json['targetTitles'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      headers: (json['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {},
      completed: (json['completed'] as List?)?.map((e) => int.tryParse(e.toString()) ?? -1).where((e) => e >= 0).toSet() ?? const {},
      failed: (json['failed'] as List?)?.map((e) => int.tryParse(e.toString()) ?? -1).where((e) => e >= 0).toSet() ?? const {},
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status']?.toString(),
        orElse: () => DownloadStatus.pending,
      ),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// 离线下载服务（DownloadService）
///
/// 设计要点：
/// 1. **任务级并发、任务内串行**：最多同时跑 [maxConcurrentTasks] 个任务，单个任务内逐项顺序下载，
///    既保证多本书并行推进，又避免单站点被高频请求打爆触发风控；
/// 2. **断点续传**：已完成下标落盘持久化，重启 App 后自动跳过已下载项继续；
/// 3. **失败熔断**：单项失败记入 `failed` 且不自动重试，由用户手动「重试失败」，杜绝死循环；
/// 4. **纯本地沙盒**：文件全部落在 App 文档目录，卸载即清除，不涉及系统相册与外部存储权限。
class DownloadService {
  static const String storageKey = 'offline_downloads';
  static const String rootDirName = 'fluxforge_offline';

  /// 同时执行的最大任务数
  static const int maxConcurrentTasks = 2;

  final ValueNotifier<List<DownloadTask>> tasksNotifier =
      ValueNotifier<List<DownloadTask>>([]);

  final RuleService _ruleService;
  final ApiClient _apiClient;

  final List<DownloadTask> _cache = [];
  final Queue<String> _queue = Queue<String>();
  final Set<String> _running = <String>{};

  DateTime _lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);

  List<DownloadTask> get tasks => tasksNotifier.value;

  DownloadService({required RuleService ruleService, ApiClient? apiClient})
      : _ruleService = ruleService,
        _apiClient = apiClient ?? ApiClient() {
    init();
  }

  /// 预热初始化：准备根目录、加载任务并恢复被中断的下载
  Future<void> init() async {
    try {
      final root = await _rootDir();
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
    } catch (e) {
      debugPrint('[DownloadService] 初始化根目录失败: $e');
    }
    await _load();
    _resumeInterrupted();
  }

  // ==================== 对外查询 ====================

  /// 查询指定书籍的下载任务
  DownloadTask? taskOf(String bookId) {
    for (final task in _cache) {
      if (task.id == bookId) return task;
    }
    return null;
  }

  /// 是否已存在该书籍的下载记录（含未完成）
  bool hasTask(String bookId) => taskOf(bookId) != null;

  /// 小说章节是否已离线下载
  /// 注意：这里用内存中的已完成集合判断，避免每次 build 都触发磁盘 IO
  bool isNovelChapterDownloaded(String bookId, int index) {
    final task = taskOf(bookId);
    if (task == null || task.mediaType != 'novel') return false;
    return task.completed.contains(index);
  }

  /// 读取已离线下载的小说章节正文（未下载返回 null）
  Future<String?> readNovelChapter(String bookId, int index) async {
    if (!isNovelChapterDownloaded(bookId, index)) return null;
    try {
      final file = await _novelChapterFile(bookId, index);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return text.isEmpty ? null : text;
    } catch (e) {
      debugPrint('[DownloadService] 读取离线章节失败: $e');
      return null;
    }
  }

  /// 获取漫画图片的本地文件路径（未下载返回 null）
  Future<String?> localComicImagePath(String bookId, String imageUrl) async {
    if (taskOf(bookId) == null) return null;
    try {
      final file = await _comicImageFile(bookId, imageUrl);
      if (await file.exists() && await file.length() > 0) return file.path;
    } catch (_) {}
    return null;
  }

  /// 统计离线下载总占用空间（字节）
  Future<int> totalBytes() async {
    try {
      final root = await _rootDir();
      if (!await root.exists()) return 0;
      int bytes = 0;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          bytes += await entity.length();
        }
      }
      return bytes;
    } catch (_) {
      return 0;
    }
  }

  // ==================== 任务创建与控制 ====================

  /// 创建（或续传）小说全本离线下载任务
  Future<DownloadTask> startNovelDownload({
    required Rule rule,
    required String bookId,
    required String title,
    required String cover,
    required List<MediaEpisode> chapters,
  }) {
    return _startTask(
      id: bookId,
      title: title,
      cover: cover,
      mediaType: 'novel',
      ruleId: rule.id?.toString() ?? rule.name,
      sourceUrl: bookId,
      targetUrls: chapters.map((e) => e.url.trim()).toList(),
      targetTitles: chapters.map((e) => e.title).toList(),
      headers: const {},
    );
  }

  /// 把「已抓取到」的章节正文落盘为离线数据（阅读器手动单章下载与跳章自动下载共用）
  ///
  /// 与全本下载**共用同一套沙盒目录、文件命名与任务记录**：
  /// - 正文统一落在 `<bookDir>/<index>.txt`；
  /// - 完成状态统一登记到本书任务的 `completed` 集合。
  ///
  /// 因此单章下载过的章节，全本下载会自动跳过（反之亦然），阅读器、目录与下载管理页
  /// 看到的始终是同一份状态 —— 不存在「缓存」与「下载」两套数据。
  /// 正文由调用方提供（阅读器抓取时本就拿到正文），可省掉一次完整网络请求。
  Future<bool> saveNovelChapterContent({
    required Rule rule,
    required String bookId,
    required String title,
    required String cover,
    required List<MediaEpisode> chapters,
    required int index,
    required String content,
  }) async {
    if (index < 0 || index >= chapters.length) return false;
    if (content.trim().isEmpty) return false;

    await _ensureNovelTask(
      rule: rule,
      bookId: bookId,
      title: title,
      cover: cover,
      chapters: chapters,
    );

    final task = taskOf(bookId);
    if (task == null) return false;
    if (task.completed.contains(index)) return true;

    try {
      final file = await _novelChapterFile(bookId, index);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
    } catch (e) {
      debugPrint('[DownloadService] 写入离线章节失败: $e');
      return false;
    }

    // 登记完成状态（与全本下载共用同一份任务记录）
    _mutate(bookId, (t) => t.copyWith(
          completed: {...t.completed, index},
          failed: t.failed.where((e) => e != index).toSet(),
          updatedAt: DateTime.now(),
        ));
    await _persist();
    return true;
  }

  /// 确保存在书籍级任务记录
  ///
  /// 单章下载时若本书尚无任务，则按「暂停」状态创建：既不自动开跑全本，
  /// 又能让阅读器目录与下载管理页读到一致的章节完成状态。
  Future<void> _ensureNovelTask({
    required Rule rule,
    required String bookId,
    required String title,
    required String cover,
    required List<MediaEpisode> chapters,
  }) async {
    if (taskOf(bookId) != null) return;

    _cache.add(DownloadTask(
      id: bookId,
      title: title,
      cover: cover,
      mediaType: 'novel',
      ruleId: rule.id?.toString() ?? rule.name,
      sourceUrl: bookId,
      targetUrls: chapters.map((e) => e.url.trim()).toList(),
      targetTitles: chapters.map((e) => e.title).toList(),
      status: DownloadStatus.paused,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    _publish();
    await _persist();
  }

  /// 创建（或续传）漫画整部离线下载任务
  Future<DownloadTask> startComicDownload({
    required Rule rule,
    required String bookId,
    required String title,
    required String cover,
    required List<String> imageUrls,
    Map<String, String> headers = const {},
  }) {
    final urls = imageUrls.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return _startTask(
      id: bookId,
      title: title,
      cover: cover,
      mediaType: 'comic',
      ruleId: rule.id?.toString() ?? rule.name,
      sourceUrl: bookId,
      targetUrls: urls,
      targetTitles: List<String>.generate(urls.length, (i) => '第 ${i + 1} 页'),
      headers: headers,
    );
  }

  /// 暂停任务
  void pause(String id) {
    _queue.removeWhere((e) => e == id);
    _mutate(id, (t) => t.copyWith(status: DownloadStatus.paused));
    unawaited(_persist());
  }

  /// 继续任务（同时清空失败集合，给予重新尝试的机会）
  void resume(String id) {
    final task = taskOf(id);
    if (task == null || task.isFinished) return;

    _mutate(
      id,
      (t) => t.copyWith(status: DownloadStatus.pending, failed: const <int>{}),
    );
    if (!_queue.contains(id)) _queue.add(id);
    _pump();
  }

  /// 仅重试失败的项
  void retryFailed(String id) {
    final task = taskOf(id);
    if (task == null || task.failed.isEmpty) return;

    _mutate(
      id,
      (t) => t.copyWith(status: DownloadStatus.pending, failed: const <int>{}),
    );
    if (!_queue.contains(id)) _queue.add(id);
    _pump();
  }

  /// 删除任务并清理其本地文件
  Future<void> remove(String id) async {
    _queue.removeWhere((e) => e == id);
    _cache.removeWhere((e) => e.id == id);
    _publish();
    await _persist();

    for (final kind in const ['novel', 'comic']) {
      try {
        final dir = await _bookDir(kind, id);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('[DownloadService] 清理下载目录失败: $e');
      }
    }
  }

  /// 清空全部下载任务与本地文件
  Future<void> clearAll() async {
    _queue.clear();
    _cache.clear();
    _publish();
    try {
      await AppStorage.remove(storageKey);
      final root = await _rootDir();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
      await root.create(recursive: true);
    } catch (e) {
      debugPrint('[DownloadService] 清空下载目录失败: $e');
    }
  }

  // ==================== 内部：任务调度 ====================

  Future<DownloadTask> _startTask({
    required String id,
    required String title,
    required String cover,
    required String mediaType,
    required String ruleId,
    required String sourceUrl,
    required List<String> targetUrls,
    required List<String> targetTitles,
    required Map<String, String> headers,
  }) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('下载任务缺少书籍唯一标识');
    }

    final existing = taskOf(id);
    final task = DownloadTask(
      id: id,
      title: title,
      cover: cover,
      mediaType: mediaType,
      ruleId: ruleId,
      sourceUrl: sourceUrl,
      targetUrls: targetUrls,
      targetTitles: targetTitles,
      headers: headers,
      // 保留已完成项实现续传；清空失败项以便重新尝试
      completed: existing?.completed ?? const <int>{},
      failed: const <int>{},
      status: DownloadStatus.pending,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _cache.removeWhere((e) => e.id == id);
    _cache.insert(0, task);
    _publish();
    await _persist();

    if (!_queue.contains(id)) _queue.add(id);
    _pump();
    return task;
  }

  /// 恢复上次退出时被中断的任务
  void _resumeInterrupted() {
    for (final task in _cache) {
      if (task.isActive) {
        _queue.add(task.id);
      } else if (task.status == DownloadStatus.paused) {
        // 暂停态保持暂停，交由用户手动继续
        continue;
      }
    }
    _pump();
  }

  /// 调度队列：在并发额度内启动任务
  void _pump() {
    while (_running.length < maxConcurrentTasks && _queue.isNotEmpty) {
      final id = _queue.removeFirst();
      if (_running.contains(id)) continue;

      final task = taskOf(id);
      if (task == null || !task.isActive) continue;

      _running.add(id);
      unawaited(
        _runTask(id).whenComplete(() {
          _running.remove(id);
          _pump();
        }),
      );
    }
  }

  /// 执行单个任务：逐项顺序下载，直到完成 / 暂停 / 失败
  Future<void> _runTask(String id) async {
    _mutate(id, (t) => t.copyWith(status: DownloadStatus.running));

    while (true) {
      final task = taskOf(id);
      // 任务被删除或已暂停 → 退出执行循环
      if (task == null || !task.isActive) return;

      final index = _nextIndex(task);
      if (index == null) {
        final allDone = task.total > 0 && task.completed.length >= task.total;
        _mutate(
          id,
          (t) => t.copyWith(
            status: allDone ? DownloadStatus.completed : DownloadStatus.failed,
          ),
        );
        await _persist();
        return;
      }

      final ok = await _downloadOne(task, index);
      if (!mountedTask(id)) return;

      _mutate(
        id,
        (t) => ok
            ? t.copyWith(completed: {...t.completed, index}, failed: {...t.failed}..remove(index))
            : t.copyWith(failed: {...t.failed, index}),
      );
      await _persistThrottled();
    }
  }

  /// 找出下一个待下载下标（跳过已完成与已失败项）
  int? _nextIndex(DownloadTask task) {
    for (int i = 0; i < task.total; i++) {
      if (task.completed.contains(i)) continue;
      if (task.failed.contains(i)) continue;
      return i;
    }
    return null;
  }

  /// 任务是否仍然存在（避免删除后继续写状态）
  bool mountedTask(String id) => taskOf(id) != null;

  /// 下载单个目标项
  Future<bool> _downloadOne(DownloadTask task, int index) async {
    if (index < 0 || index >= task.targetUrls.length) return false;
    final targetUrl = task.targetUrls[index].trim();
    if (targetUrl.isEmpty) return false;

    try {
      if (task.mediaType == 'novel') {
        return await _downloadNovelChapter(task, index, targetUrl);
      }
      return await _downloadComicImage(task, index, targetUrl);
    } catch (e) {
      debugPrint('[DownloadService] 下载失败《${task.title}》#$index: $e');
      return false;
    }
  }

  /// 小说：调度沙箱 parse 抓取正文 → 清洗 → 落盘
  Future<bool> _downloadNovelChapter(
    DownloadTask task,
    int index,
    String url,
  ) async {
    final rule = _findRule(task.ruleId);
    if (rule == null) return false;

    final res = await RuleEngine.parse(rule, url);
    final String raw = res is Map
        ? (res['content']?.toString() ?? res['text']?.toString() ?? '')
        : (res is String ? res : '');

    final content = cleanNovelContent(raw);
    if (content.isEmpty) return false;

    final file = await _novelChapterFile(task.id, index);
    await file.writeAsString(content, flush: true);
    return true;
  }

  /// 漫画：直接下载图片二进制到沙盒
  Future<bool> _downloadComicImage(
    DownloadTask task,
    int index,
    String url,
  ) async {
    final file = await _comicImageFile(task.id, url);
    if (await file.exists() && await file.length() > 0) return true;

    final response = await _apiClient.dio.download(
      url,
      file.path,
      options: Options(
        headers: task.headers.isEmpty ? null : task.headers,
        // 单张图片超时放宽，避免个别慢图拖垮整本下载
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 300) return false;
    return await file.exists() && await file.length() > 0;
  }

  /// 依据规则标识查找本地规则
  Rule? _findRule(String ruleId) {
    if (ruleId.isEmpty) return null;
    for (final rule in _ruleService.rules) {
      if (rule.id?.toString() == ruleId || rule.name == ruleId) return rule;
    }
    return null;
  }

  // ==================== 内部：状态与持久化 ====================

  void _mutate(String id, DownloadTask Function(DownloadTask) update) {
    final idx = _cache.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _cache[idx] = update(_cache[idx]);
    _publish();
  }

  void _publish() {
    tasksNotifier.value = List.unmodifiable(List<DownloadTask>.from(_cache));
  }

  Future<void> _load() async {
    try {
      final raw = await AppStorage.getString(storageKey);
      if (raw == null || raw.isEmpty) return;

      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return;

      _cache
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((e) => DownloadTask.fromJson(Map<String, dynamic>.from(e)))
              .where((t) => t.id.isNotEmpty),
        );
      _publish();
    } catch (e) {
      debugPrint('[DownloadService] 加载下载任务失败: $e');
    }
  }

  /// 节流持久化（下载过程中高频更新进度，避免频繁写 SharedPreferences）
  Future<void> _persistThrottled() async {
    final now = DateTime.now();
    if (now.difference(_lastPersistAt) < const Duration(seconds: 3)) return;
    _lastPersistAt = now;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final jsonList = _cache.map((e) => e.toJson()).toList();
      await AppStorage.setString(storageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[DownloadService] 持久化下载任务失败: $e');
    }
  }

  // ==================== 内部：文件路径 ====================

  Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, rootDirName));
  }

  Future<Directory> _bookDir(String mediaType, String bookId) async {
    final root = await _rootDir();
    final dir = Directory(
      p.join(root.path, mediaType == 'novel' ? 'novels' : 'comics', _safeName(bookId)),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _novelChapterFile(String bookId, int index) async {
    final dir = await _bookDir('novel', bookId);
    return File(p.join(dir.path, '$index.txt'));
  }

  Future<File> _comicImageFile(String bookId, String imageUrl) async {
    final dir = await _bookDir('comic', bookId);
    return File(p.join(dir.path, '${_stableHash(imageUrl)}${_extFromUrl(imageUrl)}'));
  }

  /// 书籍 ID 转安全目录名（保留可读前缀 + 稳定哈希后缀，杜绝碰撞）
  String _safeName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final head = cleaned.length > 48 ? cleaned.substring(0, 48) : cleaned;
    return '${head}_${_stableHash(raw)}';
  }

  /// 确定性字符串哈希（跨会话稳定，作为图片文件名）
  String _stableHash(String input) {
    int hash = 7;
    for (final code in input.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  /// 从图片 URL 推断扩展名（Flutter 按内容解码，不依赖扩展名，此处仅便于管理）
  String _extFromUrl(String url) {
    const allowed = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'};
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = p.extension(path).toLowerCase();
    return allowed.contains(ext) ? ext : '.img';
  }
}
