import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AdBlockEngine {
  AdBlockEngine._internal();
  static final AdBlockEngine instance = AdBlockEngine._internal();

  /// -----------------------
  /// 内部数据
  /// -----------------------
  final Set<String> _domainRules = {};
  RegExp? _combinedRegex;
  bool _isInitialized = false;

  List<String> rules = [];

  /// -----------------------
  /// 初始化规则文件
  /// -----------------------
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 这里加载你提供的规则文件
      final adFileList = [
        'adguard_base.txt',
        'adguard_chinese.txt',
        'adguard_english.txt',
        'easylist.txt',
      ];
      for (final file in adFileList) {
        final content = await _loadAsset('assets/filters/$file');
        _parseAndStoreRules(content);

        final rule = content
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.startsWith('||'))
          .where((e) => !e.startsWith('@@'))
          .toList();
        rules.addAll(rule);
      }

      _isInitialized = true;
      debugPrint('AdBlockEngine initialized: ${_domainRules.length} domain rules, regex ${_combinedRegex?.pattern.length ?? 0}');
    } catch (e) {
      debugPrint('Error initializing AdBlockEngine: $e');
      _isInitialized = true;
    }
  }

  /// -----------------------
  /// 判断是否拦截 URL
  /// -----------------------
  bool shouldBlock(String url) {
    if (!_isInitialized) return false;
    final urlLower = url.toLowerCase();

    // 普通规则匹配
    if (_domainRules.any((rule) => urlLower.contains(rule))) return true;

    // 正则匹配
    if (_combinedRegex != null && _combinedRegex!.hasMatch(urlLower)) return true;

    return false;
  }

  /// -----------------------
  /// 解析规则并存储
  /// -----------------------
  void _parseAndStoreRules(String data) {
    final regexList = <String>[];

    for (final line in data.split('\n')) {
      final rule = line.trim();

      // 跳过注释、元素隐藏、白名单
      if (rule.isEmpty || rule.startsWith('!') || rule.startsWith('#') || rule.contains('##') || rule.startsWith('@@')) {
        continue;
      }

      // 正则规则
      if (rule.startsWith('/') && rule.endsWith('/')) {
        try {
          regexList.add(rule.substring(1, rule.length - 1));
        } catch (_) {
          continue;
        }
      } else {
        // 普通字符串规则
        _domainRules.add(rule.replaceAll('*', ''));
      }
    }

    // 合并正则，减少匹配次数
    if (regexList.isNotEmpty) {
      _combinedRegex = RegExp(regexList.join('|'));
    }
  }

  /// -----------------------
  /// 读取 assets 文件
  /// -----------------------
  Future<String> _loadAsset(String path) async {
    return await rootBundle.loadString(path);
  }

  /// -----------------------
  /// 获取状态统计
  /// -----------------------
  Map<String, dynamic> get stats => {
    'domainRules': _domainRules.length,
    'regexRules': _combinedRegex?.pattern.length ?? 0,
    'isInitialized': _isInitialized,
  };
}
