// final _loggerFactory =

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final _loggerFactory = ILogger();

ILogger getLogger<T>() {
  return _loggerFactory;
}

class ILogger extends Logger {
  ILogger() : super();

  @override
  void log(Level level, dynamic message,
      {Object? error, StackTrace? stackTrace, DateTime? time}) async {
    if (level == Level.error) {
      String dir = (await getApplicationDocumentsDirectory()).path;
      // 创建logo文件
      final String filename = p.join(dir, ".logs");
      // 添加至文件末尾
      await File(filename).writeAsString(
        "**${DateTime.now()}** \n $message \n $stackTrace",
        mode: FileMode.writeOnlyAppend,
      );
    }
    super.log(level, "$message", error: error, stackTrace: stackTrace);
  }
}

Future<File> getLogsPath() async {
  String dir = (await getApplicationDocumentsDirectory()).path;
  final String filename = p.join(dir, ".logs");
  final file = File(filename);
  if (!await file.exists()) {
    await file.create();
  }
  return file;
}

Future<bool> clearLogs() async {
  String dir = (await getApplicationDocumentsDirectory()).path;
  final String filename = p.join(dir, ".logs");
  final file = File(filename);
  try {
    await file.writeAsString('');
  } catch (e) {
    debugPrint('Error clearing file: $e');
    return false;
  }
  return true;
}