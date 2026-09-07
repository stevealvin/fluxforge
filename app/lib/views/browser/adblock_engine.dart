import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 浏览器内核高性能广告与恶意追踪拦截引擎
/// 
/// 支持解析 AdGuard / EasyList 格式规则语法，提取域名规则与正则表达式
/// 实现秒级高效拦截。
class AdBlockEngine {
  AdBlockEngine._internal();

  /// 引擎单例
  static final AdBlockEngine instance = AdBlockEngine._internal();

  /// 规则存储集合
  final Set<String> _domainRules = {};
  RegExp? _combinedRegex;
  bool _isInitialized = false;

  final List<String> rules = [];

  /// 初始化本地过滤规则列表 (从 assets 中加载)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final adFileList = [
        'adguard_base.txt',
        'adguard_chinese.txt',
        'adguard_english.txt',
        'easylist.txt',
      ];
      for (final file in adFileList) {
        try {
          final content = await rootBundle.loadString('assets/filters/$file');
          _parseAndStoreRules(content);

          final extracted = content
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.startsWith('||'))
              .where((e) => !e.startsWith('@@'))
              .toList();
          rules.addAll(extracted);
        } catch (_) {
          // 容错：允许某些规则文件在特定环境不存在
        }
      }

      _isInitialized = true;
      debugPrint('【广告拦截引擎】初始化完成: ${_domainRules.length} 条域名规则, 正则长度 ${_combinedRegex?.pattern.length ?? 0}');
    } catch (e) {
      debugPrint('【广告拦截引擎】初始化异常: $e');
      _isInitialized = true;
    }
  }

  /// 判断目标 URL 是否需要拦截
  bool shouldBlock(String url) {
    if (!_isInitialized) return false;
    final urlLower = url.toLowerCase();

    // 1. 域名规则快速匹配
    if (_domainRules.any((rule) => urlLower.contains(rule))) return true;

    // 2. 正则规则深度匹配
    if (_combinedRegex != null && _combinedRegex!.hasMatch(urlLower)) return true;

    return false;
  }

  /// 解析规则文本行并存入内存集合
  void _parseAndStoreRules(String data) {
    final regexList = <String>[];

    for (final line in data.split('\n')) {
      final rule = line.trim();

      // 跳过注释、元素隐藏与白名单
      if (rule.isEmpty ||
          rule.startsWith('!') ||
          rule.startsWith('#') ||
          rule.contains('##') ||
          rule.startsWith('@@')) {
        continue;
      }

      // 正则表达式规则提取
      if (rule.startsWith('/') && rule.endsWith('/')) {
        try {
          regexList.add(rule.substring(1, rule.length - 1));
        } catch (_) {
          continue;
        }
      } else {
        // 普通域名/路径字符串规则
        _domainRules.add(rule.replaceAll('*', ''));
      }
    }

    // 合并为大正则表达式加速执行
    if (regexList.isNotEmpty) {
      _combinedRegex = RegExp(regexList.join('|'));
    }
  }

  /// 获取当前引擎状态统计信息
  Map<String, dynamic> get stats => {
        'domainRules': _domainRules.length,
        'regexRules': _combinedRegex?.pattern.length ?? 0,
        'isInitialized': _isInitialized,
      };
}
