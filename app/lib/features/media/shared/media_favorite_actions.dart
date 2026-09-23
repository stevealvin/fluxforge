import 'package:flutter/foundation.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/core/utils/media_utils.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/shared/media_download_actions.dart';

/// 详情页「收藏 / 追更」的统一动作层（收藏写入侧的唯一入口）
///
/// 三件事在此一次定死：
///
/// 1. **唯一键同源**：[key] 直接复用 [MediaDownloadActions.taskKey]，与三类详情视图
///    登记消费记录用的 `_mediaId` 完全一致（`url → 标题` 回退）。三处必须同源，
///    否则会出现「收藏了却关联不上进度」，红点判定也会错位；
/// 2. **进度不伪造**：新增收藏时写入的 `lastEpisode` 取**消费记录里的真实进度**，
///    取不到就留空，绝不用「最新集」冒充上次看到的位置；
/// 3. **动作返回文案**：与 [MediaDownloadActions] / `backup_actions.dart` 同一范式，
///    UI 只负责展示（见 `MediaDetailPage` 顶栏收藏入口）。
class MediaFavoriteActions {
  const MediaFavoriteActions._();

  /// 收藏唯一键（与下载任务、消费记录三处同源）
  static String key(MediaDetailData data, String fallbackTitle, {Rule? rule}) =>
      MediaDownloadActions.taskKey(data, fallbackTitle, rule: rule);

  /// 当前是否已收藏
  static bool isFavorited(
    MediaDetailData data,
    String fallbackTitle, {
    Rule? rule,
  }) => favoriteService.isFavorite(key(data, fallbackTitle, rule: rule));

  /// 详情数据里能表达「最新集 / 章」的文案（取末项标题；无法判断时返回空串）
  static String latestEpisodeOf(MediaDetailData data) {
    // 小说以 chapters 为准，其余以 items 为准；两者归一后取末项
    final list = data.mediaType == MediaType.novel
        ? (data.chapters.isNotEmpty ? data.chapters : data.items)
        : (data.items.isNotEmpty ? data.items : data.chapters);
    if (list.isEmpty) return '';

    final last = list.last;
    if (last.title.trim().isNotEmpty) return last.title.trim();

    final unit = switch (data.mediaType) {
      MediaType.novel => '章',
      MediaType.comic => '话',
      _ => '集',
    };
    return '第 ${list.length} $unit';
  }

  /// 本地真实进度（消费记录里的「上次看到」）
  ///
  /// 直接作为 [FavoriteService.checkUpdates] 的 `progressOf` 注入 —— 收藏库自己
  /// 不掌握进度，`FavoriteItem.lastEpisode` 只是导入备份 / 无进度时的兜底。
  static String progressOf(FavoriteItem item) {
    final episode = playHistoryService.getById(item.id)?.episodeName ?? '';
    return episode.isNotEmpty ? episode : item.lastEpisode;
  }

  /// 切换收藏状态，返回面向用户的提示文案
  static Future<String> toggle({
    required MediaDetailData data,
    required Rule? rule,
    String fallbackTitle = '',
    String fallbackCover = '',
  }) async {
    final id = key(data, fallbackTitle, rule: rule);
    if (id.isEmpty) return '无法识别该媒体，收藏失败';

    if (favoriteService.isFavorite(id)) {
      await favoriteService.removeFavorite(id);
      return '已取消收藏';
    }

    final title = data.title.isNotEmpty ? data.title : fallbackTitle;
    // 类型口径与收藏页的筛选 Tag 一致（unknown 按视频处理，与详情页分流一致）
    final mediaType = data.mediaType == MediaType.unknown
        ? MediaType.video.value
        : data.mediaType.value;

    await favoriteService.addFavorite(
      FavoriteItem(
        id: id,
        // 原文地址：进详情时原样交给规则（规则自己拼 baseUrl）
        url: data.url.trim(),
        title: title,
        cover: data.cover.isNotEmpty ? data.cover : fallbackCover,
        mediaType: mediaType,
        ruleId: rule?.id?.toString() ?? '',
        lastEpisode: playHistoryService.getById(id)?.episodeName ?? '',
        latestEpisode: latestEpisodeOf(data),
        updatedAt: DateTime.now(),
      ),
    );
    return '已加入收藏，追更已开启';
  }

  /// 规则类型 → 媒体类型（首页 / 搜索结果只有规则，没有解析后的详情）
  ///
  /// 口径与收藏页的筛选 Tag 一致：认不出来的一律按视频处理（与详情页分流同理）。
  static MediaType mediaTypeOf(Rule rule) {
    final t = rule.type.toLowerCase().trim();
    if (t == 'novel' || t == 'book' || t == 'text' || t == 'story') {
      return MediaType.novel;
    }
    if (t == 'comic' ||
        t == 'manga' ||
        t == 'image' ||
        t == 'picture' ||
        t == 'photo' ||
        t == 'gallery') {
      return MediaType.comic;
    }
    return MediaType.video;
  }

  /// 首页 / 搜索结果的收藏键：与详情页**同源**（相对地址按规则 baseUrl 归一）
  static String feedKey({
    required String title,
    required String url,
    Rule? rule,
  }) {
    final raw = url.trim();
    if (raw.isNotEmpty) {
      return resolveMediaUrl(raw, baseUrl: rule?.baseUrl ?? '');
    }
    return title.trim();
  }

  /// 首页 / 搜索结果里的条目是否已收藏
  static bool isFeedFavorited({
    required String title,
    required String url,
    Rule? rule,
  }) => favoriteService.isFavorite(feedKey(title: title, url: url, rule: rule));

  /// 从首页 / 搜索结果直接收藏（不必先解析详情）
  ///
  /// 键与类型都走上面那套与详情页共用的口径 —— 否则会出现
  /// 「详情页里收藏了、首页却显示未收藏」这种自相矛盾的状态。
  static Future<String> toggleFromFeed({
    required String title,
    required String url,
    required String cover,
    Rule? rule,
  }) async {
    final id = feedKey(title: title, url: url, rule: rule);
    if (id.isEmpty) return '无法识别该媒体，收藏失败';

    if (favoriteService.isFavorite(id)) {
      await favoriteService.removeFavorite(id);
      return '已取消收藏';
    }

    await favoriteService.addFavorite(
      FavoriteItem(
        id: id,
        url: url.trim(),
        title: title.trim().isEmpty ? '未命名' : title.trim(),
        cover: cover.trim(),
        mediaType: rule == null
            ? MediaType.video.value
            : mediaTypeOf(rule).value,
        ruleId: rule?.id?.toString() ?? '',
        lastEpisode: playHistoryService.getById(id)?.episodeName ?? '',
        // 首页只有条目元信息，还没有「最新集」；首次追更检查会自己去源站探到
        latestEpisode: '',
        updatedAt: DateTime.now(),
      ),
    );
    return '已加入收藏，追更已开启';
  }

  /// 追更探测：访问源站取该收藏项的最新集 / 章
  ///
  /// 未绑定规则或不是可访问 URL 时直接返回 null（不联网）。单项超时 / 异常一律吞掉
  /// 并返回 null —— 追更是锦上添花，不能让一个源站挂掉拖垮整次检查。
  static Future<String?> probeLatest(FavoriteItem item) async {
    if (item.ruleId.isEmpty || item.url.isEmpty) return null;

    final rule = ruleOf(item);
    if (rule == null) return null;

    try {
      final result = await RuleEngine.detail(
        rule,
        item.id,
        item: {'title': item.title, 'url': item.id, 'cover': item.cover},
      ).timeout(const Duration(seconds: 12));
      return _latestFromSandbox(result);
    } catch (e) {
      debugPrint('[MediaFavoriteActions] 追更探测失败(${item.title}): $e');
      return null;
    }
  }

  /// 从沙箱详情结果里取「最新集 / 章」文案（与详情页解析口径一致：items 优先）
  static String? _latestFromSandbox(dynamic result) {
    if (result is! Map) return null;

    List<dynamic>? raw;
    for (final key in const ['items', 'chapters']) {
      final value = result[key];
      if (value is List && value.isNotEmpty) {
        raw = value;
        break;
      }
    }
    if (raw == null) return null;

    final last = raw.last;
    if (last is Map) {
      final title = last['title']?.toString().trim() ?? '';
      if (title.isNotEmpty) return title;
    } else if (last is String && last.trim().isNotEmpty) {
      return '第 ${raw.length} 话';
    }
    return '共 ${raw.length} 项';
  }

  /// 取收藏项绑定的规则（收藏页进入详情页时必须带上）
  ///
  /// 先按记录里的 `ruleId` 精确匹配；失配（规则被删后重建、早期数据没有 ruleId）
  /// 再按 baseUrl 反查 —— 判据与详情页 / 历史页统一在 [Rule.matchesUrl]。
  static Rule? ruleOf(FavoriteItem item) {
    if (item.ruleId.isNotEmpty) {
      for (final rule in ruleService.rules) {
        if (rule.id?.toString() == item.ruleId) return rule;
      }
    }
    return ruleService.matchByUrl(item.id);
  }
}
