import 'dart:async';

/// FluxForge 全局常用纯函数与工具类集合
class AppUtils {
  AppUtils._();

  /// 智能合并基础 URL 与相对路径
  static String resolveUrl(String? baseUrl, String? targetUrl) {
    if (targetUrl == null || targetUrl.isEmpty) return '';
    if (targetUrl.startsWith('http://') || targetUrl.startsWith('https://')) {
      return targetUrl;
    }
    if (baseUrl == null || baseUrl.isEmpty) {
      return targetUrl;
    }

    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanTarget = targetUrl.startsWith('/') ? targetUrl : '/$targetUrl';
    return '$cleanBase$cleanTarget';
  }

  /// 格式化时间戳或 ISO 日期为易读字符串 (如 "2026-09-07 20:30")
  static String formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    final d = dateTime.toLocal();
    final year = d.year.toString().padLeft(4, '0');
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  /// 简短友好的相对时间 (如 "刚刚", "10分钟前", "3天前")
  static String formatRelativeTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return formatDate(dateTime);
  }

  /// 创建通用防抖器 (Debouncer)
  static void debounce(
    String tag,
    Duration duration,
    void Function() action, {
    Map<String, Timer>? timerMap,
  }) {
    final activeMap = timerMap ?? _defaultDebounceTimers;
    activeMap[tag]?.cancel();
    activeMap[tag] = Timer(duration, action);
  }

  static final Map<String, Timer> _defaultDebounceTimers = {};
}
