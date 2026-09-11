import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme/app_colors.dart';

final AppLogger _loggerInstance = AppLogger();

/// 全局统一获取日志记录器单例
AppLogger getLogger() => _loggerInstance;

/// 日志条目数据模型
class LogEntry {
  /// 日志产生时间戳
  final DateTime time;

  /// 日志级别：DEBUG, INFO, WARN, ERROR
  final String level;

  /// 日志分类标签：例如 'Rule', 'Network', 'Sandbox', 'System', 'Browser'
  final String tag;

  /// 日志主体文本信息
  final String message;

  /// 关联的异常错误对象（可选）
  final Object? error;

  /// 关联的代码异常堆栈追踪（可选）
  final StackTrace? stackTrace;

  LogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.tag = 'System',
    this.error,
    this.stackTrace,
  });

  /// 格式化时间显示 (HH:mm:ss.SSS)
  String get formattedTime {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// 根据日志级别获取对应的设计系统主色调
  Color get levelColor {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return Colors.redAccent;
      case 'WARN':
      case 'WARNING':
        return Colors.amber;
      case 'INFO':
        return AppColors.primary; // 极光翠绿
      case 'DEBUG':
      default:
        return Colors.blueAccent;
    }
  }

  /// 获取对应的语义化图标
  IconData get levelIcon {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return LucideIcons.circleAlert;
      case 'WARN':
      case 'WARNING':
        return LucideIcons.triangleAlert;
      case 'INFO':
        return LucideIcons.info;
      case 'DEBUG':
      default:
        return LucideIcons.terminal;
    }
  }

  /// 转换为单行可导出的诊断字符串
  String toExportString() {
    final buffer = StringBuffer();
    buffer.write('[$formattedTime] [$level] [$tag] $message');
    if (error != null) {
      buffer.write(' | Error: $error');
    }
    if (stackTrace != null) {
      buffer.write('\nStackTrace:\n$stackTrace');
    }
    return buffer.toString();
  }
}

/// FluxForge 全局统一高性能日志系统
class AppLogger extends Logger {
  AppLogger() : super();

  /// 内存中保存的最大日志条目上限 (先进先出，防止内存无上限占用)
  static const int maxMemoryLogs = 500;

  /// 内存中按时间倒序维护的日志列表 (最新产生的排在最前)
  static final List<LogEntry> _memoryLogs = [];

  /// 响应式日志通知器，UI 页面绑定此 Notifier 可实现零额外开销的实时响应更新
  static final ValueNotifier<List<LogEntry>> logsNotifier = ValueNotifier<List<LogEntry>>([]);

  /// 获取当前内存日志条目的只读列表拷贝
  static List<LogEntry> getLogs() => List.unmodifiable(_memoryLogs);

  /// 手动添加一条结构化日志（提供给沙箱环境与系统模块的高性能接口）
  static void addLog({
    required String level,
    required String message,
    String tag = 'System',
    Object? error,
    StackTrace? stackTrace,
    DateTime? time,
  }) {
    final now = time ?? DateTime.now();
    final entry = LogEntry(
      time: now,
      level: level.toUpperCase(),
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );

    // 插入最前（时间倒序排列）
    _memoryLogs.insert(0, entry);
    if (_memoryLogs.length > maxMemoryLogs) {
      _memoryLogs.removeLast();
    }

    // 触发响应式通知器刷新
    logsNotifier.value = List.unmodifiable(_memoryLogs);

    // 若为错误日志，异步持久化追加到本地 .logs 文件中备查
    if (entry.level == 'ERROR') {
      _appendErrorToDisk(entry);
    }
  }

  /// 异步将严重异常写入本地磁盘
  static Future<void> _appendErrorToDisk(LogEntry entry) async {
    try {
      final dir = (await getApplicationDocumentsDirectory()).path;
      final filename = p.join(dir, '.logs');
      await File(filename).writeAsString(
        '**${entry.time.toIso8601String()}** [${entry.tag}] ${entry.message}\n${entry.error ?? ""}\n${entry.stackTrace ?? ""}\n\n',
        mode: FileMode.writeOnlyAppend,
      );
    } catch (e) {
      debugPrint('[AppLogger] Failed to persist error log: $e');
    }
  }

  /// 清空内存中的全部日志并抹除磁盘历史记录
  static Future<void> clear() async {
    _memoryLogs.clear();
    logsNotifier.value = [];
    await clearLogs();
  }

  /// 将当前所有日志拼接为便于分享/复制排查的完整文本
  static String exportLogsAsText() {
    if (_memoryLogs.isEmpty) {
      return 'FluxForge 诊断日志为空。';
    }
    final buffer = StringBuffer();
    buffer.writeln('========================================');
    buffer.writeln('FluxForge 客户端诊断与运行日志导出');
    buffer.writeln('导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('日志总计: ${_memoryLogs.length} 条');
    buffer.writeln('========================================\n');

    // 导出时按时间正序排列展示，便于还原事件时序
    final chronologicalLogs = _memoryLogs.reversed.toList();
    for (final log in chronologicalLogs) {
      buffer.writeln(log.toExportString());
      buffer.writeln('----------------------------------------');
    }
    return buffer.toString();
  }

  /// 重写 logger 基类方法以无缝集成 Logger.log 调用
  @override
  void log(
    Level level,
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    DateTime? time,
  }) {
    addLog(
      level: level.name.toUpperCase(),
      message: message.toString(),
      tag: 'System',
      error: error,
      stackTrace: stackTrace,
      time: time,
    );
    super.log(level, message, error: error, stackTrace: stackTrace);
  }

  /// 规则沙箱专用快捷打印接口
  void ruleLog(String ruleName, String message, {String level = 'INFO'}) {
    addLog(
      level: level,
      tag: 'Rule: $ruleName',
      message: message,
    );
  }

  /// 网络诊断专用快捷打印接口
  void networkLog(String method, String url, {int? statusCode, String? note}) {
    final statusStr = statusCode != null ? ' [$statusCode]' : '';
    final noteStr = note != null ? ' - $note' : '';
    addLog(
      level: statusCode != null && statusCode >= 400 ? 'ERROR' : 'INFO',
      tag: 'Network',
      message: '$method $url$statusStr$noteStr',
    );
  }
}

/// 获取持久化错误日志文件句柄
Future<File> getLogsPath() async {
  final dir = (await getApplicationDocumentsDirectory()).path;
  final file = File(p.join(dir, '.logs'));
  if (!await file.exists()) {
    await file.create();
  }
  return file;
}

/// 清空历史错误日志磁盘文件
Future<bool> clearLogs() async {
  try {
    final dir = (await getApplicationDocumentsDirectory()).path;
    final file = File(p.join(dir, '.logs'));
    if (await file.exists()) {
      await file.writeAsString('');
    }
    return true;
  } catch (e) {
    debugPrint('[AppLogger] Error clearing log file: $e');
    return false;
  }
}
