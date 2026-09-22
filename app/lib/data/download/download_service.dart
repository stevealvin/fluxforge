// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fluxforge/core/network/api_client.dart';
import 'package:fluxforge/data/download/ffmpeg_command_builder.dart';
import 'package:fluxforge/data/download/hls_playlist_parser.dart';
import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/domain/text/novel_text.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/data/rule/rule_service.dart';

/// URL 失效刷新器：源站拒绝（401/403/410）时触发，宿主重新解析播放页返回新地址；
/// 返回 null 或未注册则按普通失败处理
typedef UrlExpiredRefresher = Future<String?> Function(
  DownloadTask task,
  int index,
  String staleUrl,
);

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

/// [DownloadTask.copyWith] 的「不修改」哨兵
///
/// 用来区分「没传这个参数」与「显式置空」（选集里的 `null` = 全选），
/// 否则「改回全选」这个动作没法用 `copyWith` 表达。
const Object _selectionUnchanged = Object();

/// 字节 → 可读体积（下载相关的体积展示统一走这一份，避免各处口径不一）
String formatDownloadSize(int bytes) {
  if (bytes <= 0) return '0 MB';
  final mb = bytes / (1024 * 1024);
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
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

  /// 当前正在下载项的**项内**进度（0.0 ~ 1.0）
  ///
  /// 只有「单项耗时很长」的任务才用得到：视频一集可能下载数分钟，
  /// 若只按「已完成项数」计量，进度条会长时间纹丝不动，用户会误判为卡死。
  /// 小说章节 / 漫画图片的单项都很快，恒为 0 即可，因此不影响既有行为。
  final double activeItemProgress;

  /// 选集范围（[targetUrls] 的下标；`null` = 全选）
  ///
  /// 目标清单**始终是全量**，选集只决定「跑哪些项」与「进度怎么算」。
  /// 若按选集去裁剪清单，下标就会与已完成集合错位 —— 用户只选第 5 集时，
  /// 旧的 `completed = {0,1}` 会被当成「第 0、1 集已完成」而直接跳过。
  final Set<int>? selection;

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
    this.activeItemProgress = 0,
    this.selection,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 目标总数
  int get total => targetUrls.length;

  /// 已完成数量
  int get doneCount => completed.length;

  /// 下载进度（0.0 ~ 1.0）
  ///
  /// 计入当前项的项内进度（[activeItemProgress]），使长视频下载时进度条能持续前进；
  /// 小说 / 漫画的项内进度恒为 0，因此结果与改造前完全一致。
  double get progress {
    final selected = selectedTotal;
    if (selected == 0) return 0.0;
    return ((selectedDoneCount + activeItemProgress) / selected).clamp(
      0.0,
      1.0,
    );
  }

  /// 是否处于可继续调度状态
  bool get isActive =>
      status == DownloadStatus.pending || status == DownloadStatus.running;

  /// 是否全部完成
  bool get isFinished => status == DownloadStatus.completed;

  /// 本次要跑的项数（选集只算选中项；`null` = 全选）
  int get selectedTotal {
    final sel = selection;
    if (sel == null) return total;
    return sel.where((i) => i >= 0 && i < total).length;
  }

  /// 选中项中已完成的数量
  int get selectedDoneCount {
    final sel = selection;
    if (sel == null) return doneCount;
    return completed.where(sel.contains).length;
  }

  /// 是否为「选集下载」（用于文案区分：全本 / 选集）
  bool get isPartialSelection => selection != null;

  /// 某一项是否在本次下载范围内
  bool isSelected(int index) {
    if (index < 0 || index >= total) return false;
    final sel = selection;
    return sel == null || sel.contains(index);
  }

  /// 进度文案
  String get progressLabel => '$selectedDoneCount / $selectedTotal';

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
    double? activeItemProgress,
    Object? selection = _selectionUnchanged,
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
      activeItemProgress: activeItemProgress ?? this.activeItemProgress,
      selection: identical(selection, _selectionUnchanged)
          ? this.selection
          : selection as Set<int>?,
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
      'activeItemProgress': activeItemProgress,
      'selection': selection?.toList(),
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
      targetUrls:
          (json['targetUrls'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      targetTitles:
          (json['targetTitles'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      headers:
          (json['headers'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const {},
      completed:
          (json['completed'] as List?)
              ?.map((e) => int.tryParse(e.toString()) ?? -1)
              .where((e) => e >= 0)
              .toSet() ??
          const {},
      failed:
          (json['failed'] as List?)
              ?.map((e) => int.tryParse(e.toString()) ?? -1)
              .where((e) => e >= 0)
              .toSet() ??
          const {},
      // 缺字段 = 改造前的老任务 = 全选（语义与从前一致，无需迁移）
      selection: (json['selection'] as List?)
          ?.map((e) => int.tryParse(e.toString()) ?? -1)
          .where((e) => e >= 0)
          .toSet(),
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status']?.toString(),
        orElse: () => DownloadStatus.pending,
      ),
      // 项内进度属瞬时状态：重启后旧值无意义，一律从 0 重新计
      activeItemProgress: 0,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
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

  /// 正在执行的「视频下载」FFmpeg 会话（任务 id → sessionId）
  ///
  /// 视频下载是单条 FFmpeg 会话的长任务，pause / 删除任务时必须主动 cancel 对应会话，
  /// 否则 FFmpeg 会继续把整部视频拉完，白白消耗流量与电量。
  final Map<String, int> _videoSessions = <String, int>{};

  /// 正在进行的直链下载取消令牌（任务 id → token）
  ///
  /// 直链视频的单个请求可能持续数十分钟，暂停 / 删除任务时必须打断流式读取，
  /// 已下载字节保留在 `.part` 文件中供下次续传。
  final Map<String, CancelToken> _videoCancelTokens = <String, CancelToken>{};

  /// URL 过期刷新回调（可空）：源站 401/403/410 时触发，宿主重新解析播放页换新地址
  final UrlExpiredRefresher? onUrlExpired;

  DateTime _lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);

  List<DownloadTask> get tasks => tasksNotifier.value;

  DownloadService({
    required RuleService ruleService,
    ApiClient? apiClient,
    this.onUrlExpired,
  }) : _ruleService = ruleService,
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
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          bytes += await entity.length();
        }
      }
      return bytes;
    } catch (_) {
      return 0;
    }
  }

  /// 某任务已落盘的**成品**体积（字节）
  ///
  /// 只扫书目录**本层**：小说章节、漫画图片、视频成品都直接落在该层，
  /// 而视频的分片工作目录是它的子目录（合并成功即整目录删除），
  /// 因此非递归扫描天然排除中间产物，不会把"半截文件"算进已下载体积。
  Future<int> taskBytes(DownloadTask task) async {
    try {
      final dir = await _bookDir(task.mediaType, task.id);
      if (!await dir.exists()) return 0;
      var bytes = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        bytes += await entity.length();
      }
      return bytes;
    } catch (_) {
      return 0;
    }
  }

  /// 探测一组直链的**预计大小**（字节；该项未知为 `null`）
  ///
  /// 只对单文件直链有效：`Content-Length` 就是文件大小。
  /// HLS（`.m3u8`）要把清单里每一片都问一遍才知道总量，成本远高于收益，
  /// 因此直接返回 `null` —— 宁可不显示，也不显示一个错得离谱的数字。
  Future<List<int?>> probeUnitSizes(
    List<String> urls, {
    Map<String, String> headers = const {},
  }) async {
    final sizes = <int?>[];
    for (final url in urls) {
      sizes.add(await _probeSize(url, headers: headers));
    }
    return sizes;
  }

  Future<int?> _probeSize(
    String url, {
    required Map<String, String> headers,
  }) async {
    final target = url.trim();
    if (target.isEmpty || target.contains('.m3u8')) return null;
    try {
      final response = await _apiClient.dio.head<void>(
        target,
        options: Options(
          headers: headers,
          // 探测只服务展示，绝不能拖住面板：短超时，失败即"未知"
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final length = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      return (length != null && length > 0) ? length : null;
    } catch (_) {
      // 部分源站不支持 HEAD / 需要 Range 才回长度 → 视为未知
      return null;
    }
  }

  /// 把「原清单下标」的选集映射到「过滤后清单下标」
  ///
  /// 过滤掉空地址后下标会整体前移，直接沿用原下标会选错集。
  static Set<int>? _remapSelection(
    Set<int>? selection,
    List<int> keptOriginalIndices,
  ) {
    if (selection == null) return null;
    final mapped = <int>{};
    for (int i = 0; i < keptOriginalIndices.length; i++) {
      if (selection.contains(keptOriginalIndices[i])) mapped.add(i);
    }
    if (mapped.isEmpty) return const {};
    return mapped;
  }

  // ==================== 任务创建与控制 ====================

  /// 创建（或续传）小说全本离线下载任务
  Future<DownloadTask> startNovelDownload({
    required Rule rule,
    required String bookId,
    required String title,
    required String cover,
    required List<MediaEpisode> chapters,
    Set<int>? selectedIndices,
  }) {
    return _startTask(
      id: bookId,
      title: title,
      cover: cover,
      mediaType: 'novel',
      selection: selectedIndices,
      ruleId: rule.id?.toString() ?? '',
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
    _mutate(
      bookId,
      (t) => t.copyWith(
        completed: {...t.completed, index},
        failed: t.failed.where((e) => e != index).toSet(),
        updatedAt: DateTime.now(),
      ),
    );
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

    _cache.add(
      DownloadTask(
        id: bookId,
        title: title,
        cover: cover,
        mediaType: 'novel',
        ruleId: rule.id?.toString() ?? '',
        sourceUrl: bookId,
        targetUrls: chapters.map((e) => e.url.trim()).toList(),
        targetTitles: chapters.map((e) => e.title).toList(),
        status: DownloadStatus.paused,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
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
    Set<int>? selectedIndices,
  }) {
    final urls = imageUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return _startTask(
      id: bookId,
      title: title,
      cover: cover,
      mediaType: 'comic',
      ruleId: rule.id?.toString() ?? '',
      sourceUrl: bookId,
      selection: selectedIndices,
      targetUrls: urls,
      targetTitles: List<String>.generate(urls.length, (i) => '第 ${i + 1} 页'),
      headers: headers,
    );
  }

  /// 创建（或续传）视频整部离线下载任务
  ///
  /// [episodes] 为待下载分集（标题 + 播放地址），地址通常是 m3u8 清单或 mp4 直链；
  /// 产物统一落在 `videos/<书籍ID>/<索引>.mp4`。
  ///
  /// [headers] 用于防盗链站点（Referer / User-Agent / Cookie 等），
  /// 会透传给 FFmpeg 的输入侧选项（详见 [FfmpegCommandBuilder.buildHeaderArgs]）。
  Future<DownloadTask> startVideoDownload({
    required Rule rule,
    required String bookId,
    required String title,
    required String cover,
    required List<MediaEpisode> episodes,
    Map<String, String> headers = const {},
    Set<int>? selectedIndices,
  }) {
    // 过滤掉无有效地址的分集：FFmpeg 面对空地址只会白跑一轮再失败。
    // 注意：过滤会改变下标，因此选集必须**按下标映射**（调用方传的是原清单下标）
    final valid = episodes.where((e) => e.url.trim().isNotEmpty).toList();
    final validIndices = <int>[
      for (int i = 0; i < episodes.length; i++)
        if (episodes[i].url.trim().isNotEmpty) i,
    ];
    return _startTask(
      id: bookId,
      title: title,
      cover: cover,
      mediaType: 'video',
      ruleId: rule.id?.toString() ?? '',
      sourceUrl: bookId,
      selection: _remapSelection(selectedIndices, validIndices),
      targetUrls: valid.map((e) => e.url.trim()).toList(),
      targetTitles: valid.map((e) => e.title).toList(),
      headers: headers,
    );
  }

  /// 某一集视频是否已下载完成
  ///
  /// 与 [isNovelChapterDownloaded] 同一约定：依据内存中的任务记录判断，
  /// 避免每次 build 都触发磁盘 IO。
  bool isVideoEpisodeDownloaded(String bookId, int index) {
    final task = taskOf(bookId);
    if (task == null || task.mediaType != 'video') return false;
    return task.completed.contains(index);
  }

  /// 查询已下载视频的本地路径（未下载返回 null）
  ///
  /// 供播放器使用：`video_player` 直接支持本地文件路径。
  Future<String?> localVideoPath(String bookId, int index) async {
    final task = taskOf(bookId);
    if (task == null || task.mediaType != 'video') return null;
    if (!task.completed.contains(index)) return null;

    final file = await _videoFile(bookId, index);
    if (!await file.exists() || await file.length() <= 0) return null;
    return file.path;
  }

  /// 暂停任务
  void pause(String id) {
    _queue.removeWhere((e) => e == id);
    // 视频下行任务必须显式终止：FFmpeg 会话与直链流式请求两条通道都要打断，
    // 否则它会继续把整部视频拉完，白白消耗流量与电量
    final sessionId = _videoSessions.remove(id);
    if (sessionId != null && sessionId > 0) {
      unawaited(FFmpegKit.cancel(sessionId));
    }
    _videoCancelTokens.remove(id)?.cancel('任务已暂停');
    _mutate(
      id,
      (t) => t.copyWith(
        status: DownloadStatus.paused,
        // 项内进度属瞬时状态，暂停即作废
        activeItemProgress: 0,
      ),
    );
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
    // 终止所有还在跑的视频下载会话（须在清空 _videoSessions 之前收集）
    for (final sessionId in _videoSessions.values) {
      if (sessionId > 0) unawaited(FFmpegKit.cancel(sessionId));
    }
    _videoSessions.clear();
    for (final token in _videoCancelTokens.values) {
      token.cancel('清空全部下载');
    }
    _videoCancelTokens.clear();
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
    Set<int>? selection,
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
      // 选集：本次显式传入即**替换**（目标清单始终全量，替换不会错位，
      // 也不会丢掉已完成的项）；`null` 即「全部下载」
      selection: selection,
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
        // 只按**选中项**判定完成：选集下载时未选中的项本来就不会跑，
        // 若拿全量计数作判据，任务会永远等不到「全部完成」
        final allDone =
            task.selectedTotal > 0 &&
            task.selectedDoneCount >= task.selectedTotal;
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
            ? t.copyWith(
                completed: {...t.completed, index},
                failed: {...t.failed}..remove(index),
              )
            : t.copyWith(failed: {...t.failed, index}),
      );
      await _persistThrottled();
    }
  }

  /// 找出下一个待下载下标（跳过已完成与已失败项）
  int? _nextIndex(DownloadTask task) {
    for (int i = 0; i < task.total; i++) {
      // 未选中的项直接跳过：它们不该被下载，也不该影响进度
      if (!task.isSelected(i)) continue;
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
      if (task.mediaType == 'video') {
        return await _downloadVideoEpisode(task, index, targetUrl);
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

  /// 视频下载分派：按地址形态选择续传策略
  ///
  /// - m3u8（HLS 清单）→ 分片级续传：逐分片落盘，已完成的跳过；
  /// - 其余（mp4 / mkv 等直链）→ HTTP Range 字节级续传。
  /// 两者的共同点：**任何中断都不会丢掉已下载的部分**。
  Future<bool> _downloadVideoEpisode(DownloadTask task, int index, String url) {
    return _downloadVideoEpisodeGuarded(task, index, url, allowRefresh: true);
  }

  /// 下载一集；URL 失效（401/403/410）时刷新地址重试一次，已下载进度保留
  Future<bool> _downloadVideoEpisodeGuarded(
    DownloadTask task,
    int index,
    String url, {
    required bool allowRefresh,
  }) async {
    try {
      return _isHlsUrl(url)
          ? await _downloadHlsEpisode(task, index, url)
          : await _downloadDirectVideo(task, index, url);
    } on _UrlExpiredException {
      if (!allowRefresh) return false;
      final refresher = onUrlExpired;
      if (refresher == null) return false;

      // 暂停 / 删除后不再触发刷新
      final live = taskOf(task.id);
      if (live == null || !live.isActive) return false;

      final fresh = await refresher(task, index, url);
      final freshUrl = fresh?.trim() ?? '';
      if (freshUrl.isEmpty || freshUrl == url.trim()) return false;

      // 新地址登记回任务：本次重试与后续「重试失败」都用它
      _mutate(task.id, (t) {
        if (index >= t.targetUrls.length) return t;
        final urls = [...t.targetUrls]..[index] = freshUrl;
        return t.copyWith(targetUrls: urls, updatedAt: DateTime.now());
      });

      // HLS：含冻结签名的旧清单必须作废重拉；分片本身与签名无关，保留续传
      if (_isHlsUrl(freshUrl)) {
        try {
          final workDir = await _videoWorkDir(task.id, index);
          final stale = File(p.join(workDir.path, 'remote.m3u8'));
          if (await stale.exists()) await stale.delete();
        } catch (_) {}
      }

      return _downloadVideoEpisodeGuarded(
        task,
        index,
        freshUrl,
        allowRefresh: false,
      );
    }
  }

  /// 是否为 HLS 清单地址
  ///
  /// 依据扩展名判断：绝大多数站点都会带 `.m3u8`。对无扩展名的地址，
  /// 直链 Range 续传是更安全的兜底（误判成直链只会少一次解密机会，不会失败）。
  static bool _isHlsUrl(String url) => url.toLowerCase().contains('.m3u8');

  /// 401/403/410 视为 URL 失效；超时、断网、5xx 刷新无意义
  static bool isAuthExpiredStatus(int? statusCode) =>
      statusCode == 401 || statusCode == 403 || statusCode == 410;

  /// 拉取清单文本；被源站拒绝（401/403/410）时转译为 [_UrlExpiredException]
  Future<String> _getPlaylistText(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final res = await _apiClient.dio.get<String>(
        url,
        options: Options(headers: headers, responseType: ResponseType.plain),
      );
      return res.data ?? '';
    } on DioException catch (e) {
      if (isAuthExpiredStatus(e.response?.statusCode)) {
        throw _UrlExpiredException(e.response?.statusCode ?? 0);
      }
      rethrow;
    }
  }

  /// HLS：分片级断点续传
  ///
  /// 1. 下载清单（**优先复用上次已存清单** —— 源站临时不可达时也能续传）；
  /// 2. master 多码率清单取第一个码率子清单再解析一层；
  /// 3. 逐个下载资源（分片 / 密钥 / 初始化段），**已存在的直接跳过** —— 续传的核心；
  /// 4. 改写出指向本地文件的清单，交给 FFmpeg 合并（AES 解密由其 crypto 协议完成）；
  /// 5. 合并成功后删除分片目录，只保留最终 MP4。
  ///
  /// 分片写入统一「先写 `.tmp` 再改名」：保证磁盘上存在的分片一定是完整的，
  /// 中断不会留下半截分片被误判为已下载。
  Future<bool> _downloadHlsEpisode(
    DownloadTask task,
    int index,
    String url,
  ) async {
    final workDir = await _videoWorkDir(task.id, index);
    await workDir.create(recursive: true);
    final playlistFile = File(p.join(workDir.path, 'remote.m3u8'));

    // 1. 清单文本
    String playlistText;
    if (await playlistFile.exists()) {
      playlistText = await playlistFile.readAsString();
    } else {
      playlistText = await _getPlaylistText(url, task.headers);
      if (playlistText.trim().isEmpty) return false;
      await playlistFile.writeAsString(playlistText, flush: true);
    }

    var baseUri = Uri.parse(url);
    var playlist = HlsPlaylistParser.parse(playlistText, baseUri);

    // 2. master 清单：取第一个码率子清单再解析一层
    if (playlist.isMaster) {
      if (playlist.variantUrls.isEmpty) return false;
      final variantUrl = playlist.variantUrls.first;
      playlistText = await _getPlaylistText(variantUrl, task.headers);
      baseUri = Uri.parse(variantUrl);
      playlist = HlsPlaylistParser.parse(playlistText, baseUri);
      if (playlist.segmentUrls.isEmpty) return false;
      await playlistFile.writeAsString(playlistText, flush: true);
    }

    // 3. 逐资源下载
    final resources = playlist.resourceUrls;
    final remoteToLocal = <String, String>{};
    var lastPublishAt = DateTime.fromMillisecondsSinceEpoch(0);

    for (var i = 0; i < resources.length; i++) {
      // 每个分片之间检查任务存活性：暂停 / 删除后立即中止，不再消耗流量
      final live = taskOf(task.id);
      if (live == null || !live.isActive) return false;

      final remote = resources[i];
      final isSegment = playlist.segmentUrls.contains(remote);
      final fileName = isSegment
          ? 'seg_${i.toString().padLeft(4, '0')}'
          : 'res_${i.toString().padLeft(4, '0')}';
      final target = File(p.join(workDir.path, fileName));
      remoteToLocal[remote] = fileName;

      // 续传核心：已存在的分片直接跳过
      if (await target.exists() && await target.length() > 0) continue;

      final tmp = File('${target.path}.tmp');
      try {
        await _apiClient.dio.download(
          remote,
          tmp.path,
          options: Options(
            headers: task.headers,
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        if (!await tmp.exists() || await tmp.length() <= 0) return false;
        await tmp.rename(target.path);
      } on DioException catch (e) {
        // 源站拒绝（401/403/410）→ 上抛交「URL 过期刷新」编排，临时文件照常清理
        if (await tmp.exists()) await tmp.delete();
        if (isAuthExpiredStatus(e.response?.statusCode)) {
          throw _UrlExpiredException(e.response?.statusCode ?? 0);
        }
        debugPrint('[DownloadService] HLS 分片下载失败《${task.title}》#$index/$i: $e');
        return false;
      } catch (e) {
        debugPrint('[DownloadService] HLS 分片下载失败《${task.title}》#$index/$i: $e');
        if (await tmp.exists()) await tmp.delete();
        return false;
      }

      // 分片粒度进度（500ms 节流）
      final now = DateTime.now();
      if (now.difference(lastPublishAt).inMilliseconds >= 500) {
        lastPublishAt = now;
        if (mountedTask(task.id)) {
          _mutate(
            task.id,
            (t) => t.copyWith(
              activeItemProgress: (i + 1) / resources.length,
              updatedAt: now,
            ),
          );
        }
      }
    }

    // 4. 改写清单为本地引用（分片 + 密钥全部指向本地文件）
    final localPlaylist = File(p.join(workDir.path, 'local.m3u8'));
    await localPlaylist.writeAsString(
      HlsPlaylistParser.rewriteToLocal(playlistText, baseUri, remoteToLocal),
      flush: true,
    );

    // 5. FFmpeg 合并（AES 解密由其 crypto 协议完成）
    final outputFile = await _videoFile(task.id, index);
    final ok = await _runFfmpeg(
      taskId: task.id,
      command: FfmpegCommandBuilder.buildLocalMerge(
        playlistPath: localPlaylist.path,
        outputPath: outputFile.path,
      ),
      failLabel: 'HLS 合并失败《${task.title}》#$index',
    );
    if (!ok) return false;

    // 6. 合并成功后清掉分片目录，只保留最终 MP4
    try {
      await workDir.delete(recursive: true);
    } catch (_) {}

    return await outputFile.exists() && await outputFile.length() > 0;
  }

  /// 直链视频：HTTP Range 字节级断点续传
  ///
  /// mp4 / mkv 等单文件直链不需要 FFmpeg —— 按字节区间续传更快也更省电：
  /// - 中断后已有字节保留在 `.part` 文件，继续时带 `Range: bytes=<已有>-` 请求；
  /// - 服务器不支持 Range（返回 200）时自动退化为整文件重下；
  /// - 完成后**原子改名**为正式 MP4，杜绝「半截文件被当成品」。
  Future<bool> _downloadDirectVideo(
    DownloadTask task,
    int index,
    String url,
  ) async {
    final finalFile = await _videoFile(task.id, index);
    await finalFile.parent.create(recursive: true);
    final partFile = File('${finalFile.path}.part');

    final downloaded = (await partFile.exists()) ? await partFile.length() : 0;

    final cancelToken = CancelToken();
    if (downloaded > 0) _videoCancelTokens[task.id] = cancelToken;

    final Response<ResponseBody> response;
    try {
      response = await _apiClient.dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {
            ...task.headers,
            if (downloaded > 0) 'Range': 'bytes=$downloaded-',
          },
          responseType: ResponseType.stream,
          // 单集视频很大，接收超时必须放宽；连接超时由 Dio 全局配置兜底
          receiveTimeout: const Duration(minutes: 2),
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      _videoCancelTokens.remove(task.id);
      // 用户主动暂停：保留 .part 供下次续传
      if (e.type == DioExceptionType.cancel) return false;
      // 源站拒绝（401/403/410）→ 上抛交「URL 过期刷新」编排，.part 保留续传
      if (isAuthExpiredStatus(e.response?.statusCode)) {
        throw _UrlExpiredException(e.response?.statusCode ?? 0);
      }
      rethrow;
    } catch (_) {
      _videoCancelTokens.remove(task.id);
      rethrow;
    }
    _videoCancelTokens.remove(task.id);

    final code = response.statusCode ?? 0;
    // 206 = 服务器支持续传；200 = 不支持 Range，只能整文件重下
    final canResume = code == 206;
    if (code != 206 && code != 200) return false;

    final contentLength =
        int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        0;
    // 续传时 Content-Length 只是剩余字节数
    final totalBytes = canResume ? downloaded + contentLength : contentLength;

    if (!canResume && downloaded > 0) {
      // 服务器忽略了 Range：丢弃旧 .part 从头来
      await partFile.delete();
    }

    final sink = partFile.openWrite(
      mode: canResume ? FileMode.append : FileMode.write,
    );
    var received = canResume ? downloaded : 0;
    var lastPublishAt = DateTime.fromMillisecondsSinceEpoch(0);

    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes <= 0) continue;
        final now = DateTime.now();
        if (now.difference(lastPublishAt).inMilliseconds < 500) continue;
        lastPublishAt = now;
        if (!mountedTask(task.id)) break;
        _mutate(
          task.id,
          (t) => t.copyWith(
            activeItemProgress: (received / totalBytes).clamp(0.0, 1.0),
            updatedAt: now,
          ),
        );
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      // 中断：保留 .part 供下次续传
      debugPrint('[DownloadService] 直链下载中断《${task.title}》#$index: $e');
      return false;
    }

    if (received <= 0) return false;
    await partFile.rename(finalFile.path);
    return true;
  }

  /// 执行一条 FFmpeg 命令并回报项内进度
  ///
  /// - 用 [FFmpegKit.executeAsync] 而非 `execute`：后者要等命令跑完才返回，
  ///   期间无法响应「暂停 / 删除任务」的取消请求；
  /// - 进度来自 [Statistics.getTime] 与日志中的 `Duration:` 摘要行 ——
  ///   **不额外发起 FFprobe 请求**：带防盗链头的源它也发不了；
  /// - 统计回调非常密集，做了 500ms 节流，否则下载列表会每秒重建几十次。
  Future<bool> _runFfmpeg({
    required String taskId,
    required String command,
    required String failLabel,
  }) async {
    final completer = Completer<bool>();
    Duration? totalDuration;
    var lastPublishAt = DateTime.fromMillisecondsSinceEpoch(0);

    final session = await FFmpegKit.executeAsync(
      command,
      // 完成回调：以返回码判定成败
      (session) async {
        final returnCode = await session.getReturnCode();
        final ok = ReturnCode.isSuccess(returnCode);
        if (!ok && !ReturnCode.isCancel(returnCode)) {
          final allLogs = await session.getLogs();
          final tail = allLogs.length > 8
              ? allLogs.sublist(allLogs.length - 8)
              : allLogs;
          final tailText = tail
              .map((l) => l.getMessage())
              .where((m) => m.trim().isNotEmpty)
              .join('\n');
          debugPrint(
            '[DownloadService] $failLabel rc=${returnCode?.getValue()}\n$tailText',
          );
        }
        if (!completer.isCompleted) completer.complete(ok);
      },
      // 日志回调：只抓一次媒体总时长
      (log) {
        totalDuration ??= FfmpegCommandBuilder.parseDurationFromLog(
          log.getMessage(),
        );
      },
      // 统计回调：换算项内进度（500ms 节流）
      (statistics) {
        final ratio = FfmpegCommandBuilder.progressRatio(
          processedMillis: statistics.getTime(),
          totalDuration: totalDuration,
        );
        if (ratio == null) return;
        final now = DateTime.now();
        if (now.difference(lastPublishAt).inMilliseconds < 500) return;
        lastPublishAt = now;
        if (!mountedTask(taskId)) return;
        _mutate(
          taskId,
          (t) => t.copyWith(activeItemProgress: ratio, updatedAt: now),
        );
      },
    );

    // getSessionId 可能为 null（会话未成功登记）；0 同样视为无效 ——
    // FFmpegKit.cancel(null) 语义是「取消全部会话」，绝不能把无效值传进去
    final sessionId = session.getSessionId() ?? 0;
    if (sessionId > 0) _videoSessions[taskId] = sessionId;
    // 会话启动瞬间任务可能已被暂停 / 删除，此时立即终止 FFmpeg
    final live = taskOf(taskId);
    if (live == null || !live.isActive) {
      if (sessionId > 0) await FFmpegKit.cancel(sessionId);
    }

    final ok = await completer.future;
    _videoSessions.remove(taskId);

    // 无论成败都清掉项内进度，避免任务收尾时进度条停在半路
    if (mountedTask(taskId)) {
      _mutate(
        taskId,
        (t) => t.copyWith(activeItemProgress: 0, updatedAt: DateTime.now()),
      );
    }
    return ok;
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
      p.join(root.path, _mediaDirName(mediaType), _safeName(bookId)),
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
    return File(
      p.join(dir.path, '${_stableHash(imageUrl)}${_extFromUrl(imageUrl)}'),
    );
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

  /// 媒体类型 → 沙盒子目录名
  ///
  /// 视频沿用同一套根目录与任务记录，只是落在独立的 `videos/` 子树，
  /// 与小说 / 漫画互不干扰，也便于按类型清理。
  static String _mediaDirName(String mediaType) => switch (mediaType) {
    'novel' => 'novels',
    'comic' => 'comics',
    'video' => 'videos',
    _ => 'others',
  };

  /// 视频分集文件路径（`videos/<bookId>/<index>.mp4`）
  ///
  /// 以索引命名而非集标题：集标题可能含非法字符且可能重复，索引进沙盒后
  /// 天然有序，播放时再从 `targetTitles` 取标题展示。
  Future<File> _videoFile(String bookId, int index) async {
    final dir = await _bookDir('video', bookId);
    return File(p.join(dir.path, '$index.mp4'));
  }

  /// 视频分片工作目录（`videos/<bookId>/<index>/`），合并成功后整体删除
  Future<Directory> _videoWorkDir(String bookId, int index) async {
    final dir = await _bookDir('video', bookId);
    return Directory(p.join(dir.path, '$index'));
  }
}

/// 内部信号：源站以 401/403/410 拒绝请求，交由上层编排「刷新 URL 重试」
class _UrlExpiredException implements Exception {
  const _UrlExpiredException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'UrlExpired(status: $statusCode)';
}
