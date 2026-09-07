import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final AppLogger _loggerInstance = AppLogger();

AppLogger getLogger() => _loggerInstance;

/// 日志条目模型
class LogEntry {
  final DateTime time;
  final String level;
  final String message;

  LogEntry({
    required this.time,
    required this.level,
    required this.message,
  });
}

/// FluxForge 全局统一日志记录器
class AppLogger extends Logger {
  AppLogger() : super();

  /// 内存中保存的最近日志记录 (最多保留 200 条)
  static final List<LogEntry> _memoryLogs = [];

  /// 获取当前内存日志条目
  static List<LogEntry> getLogs() => List.unmodifiable(_memoryLogs);

  /// 清空内存与磁盘日志
  static Future<void> clear() async {
    _memoryLogs.clear();
    await clearLogs();
  }

  @override
  void log(
    Level level,
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    DateTime? time,
  }) async {
    final now = time ?? DateTime.now();
    final entry = LogEntry(
      time: now,
      level: level.name.toUpperCase(),
      message: '$message${error != null ? ' | error: $error' : ''}',
    );

    _memoryLogs.insert(0, entry);
    if (_memoryLogs.length > 200) {
      _memoryLogs.removeLast();
    }

    if (level == Level.error) {
      try {
        final dir = (await getApplicationDocumentsDirectory()).path;
        final filename = p.join(dir, '.logs');
        await File(filename).writeAsString(
          '**$now** \n$message \n$stackTrace\n\n',
          mode: FileMode.writeOnlyAppend,
        );
      } catch (e) {
        debugPrint('[AppLogger] Failed to persist error log: $e');
      }
    }
    super.log(level, '$message', error: error, stackTrace: stackTrace);
  }
}

/// 获取日志文件
Future<File> getLogsPath() async {
  final dir = (await getApplicationDocumentsDirectory()).path;
  final file = File(p.join(dir, '.logs'));
  if (!await file.exists()) {
    await file.create();
  }
  return file;
}

/// 清空历史错误日志
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
