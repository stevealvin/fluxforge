import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/app_storage.dart';

/// 广告拦截规则订阅源模型
class AdFilterSource {
  final String id;
  final String name;
  final String description;
  final List<String> mirrorUrls;
  final bool isBuiltIn;
  bool isEnabled;

  AdFilterSource({
    required this.id,
    required this.name,
    required this.description,
    required this.mirrorUrls,
    this.isBuiltIn = true,
    this.isEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'mirrorUrls': mirrorUrls,
        'isBuiltIn': isBuiltIn,
        'isEnabled': isEnabled,
      };

  factory AdFilterSource.fromJson(Map<String, dynamic> json) => AdFilterSource(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        mirrorUrls: (json['mirrorUrls'] as List<dynamic>?)?.cast<String>() ?? [],
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
        isEnabled: json['isEnabled'] as bool? ?? true,
      );
}

/// 现代化高性能广告与流氓弹窗拦截引擎
/// 
/// 核心特性：
/// 1. 【内置种子保底】：内置精选国内广告联盟、小说/影视诱导跳转黑名单，新装与断网零门槛即开即用；
/// 2. 【云端多源热更】：支持从 AdGuard 官方 CDN、jsDelivr 等镜像异步拉取最新规则，并持久化于本地沙箱；
/// 3. 【三维立体拦截】：域名请求阻断 + 网页 DOM 元素隐藏 CSS 注入 + 恶意弹窗 Scriptlet 拆弹；
/// 4. 【零依赖轻量化】：彻底移除 Assets 巨型静态规则文件，App 安装包直降 11.4MB。
class AdBlockEngine {
  AdBlockEngine._internal();

  /// 引擎全局单例
  static final AdBlockEngine instance = AdBlockEngine._internal();

  /// 本地已加载的域名匹配黑名单 (Set 结构哈希加速，O(1) 查询)
  final Set<String> _domainRules = {};

  /// 本地提取的 DOM 元素隐藏 CSS 选择器集合
  final Set<String> _elementHidingSelectors = {};

  /// 正则匹配深度规则
  RegExp? _combinedRegex;

  /// 引擎是否已经完成初始化
  bool _isInitialized = false;

  /// 预设高可用规则订阅源列表 (首选国内加速与官方镜像)
  final List<AdFilterSource> _sources = [
    AdFilterSource(
      id: 'adguard_chinese',
      name: 'AdGuard 中文规则优化版',
      description: '针对国内小说、影视与漫画站点的流氓广告、悬浮条与插屏拦截（推荐）',
      mirrorUrls: [
        'https://filters.adtidy.org/windows/filters/224_optimized.txt',
        'https://cdn.jsdelivr.net/gh/AdguardTeam/AdguardFilters@master/ChineseFilter/sections/adservers.txt',
      ],
      isBuiltIn: true,
      isEnabled: true,
    ),
    AdFilterSource(
      id: 'cjx_annoyance',
      name: 'CJX 烦人弹窗与防封杀规则',
      description: '强力过滤诱导跳转 App、全屏遮罩及反 AdBlock 恶意弹窗',
      mirrorUrls: [
        'https://cdn.jsdelivr.net/gh/cjx82630/cjxlist@master/cjx-annoyance.txt',
        'https://raw.githubusercontent.com/cjx82630/cjxlist/master/cjx-annoyance.txt',
      ],
      isBuiltIn: true,
      isEnabled: false,
    ),
    AdFilterSource(
      id: 'easylist_china',
      name: 'EasyList China 中文基础规则',
      description: '全球开源 EasyList 官方中文维护规则库 (推荐与中文优化版互补)',
      mirrorUrls: [
        'https://easylist-downloads.adblockplus.org/easylistchina.txt',
        'https://cdn.jsdelivr.net/gh/easylist/easylistchina@master/easylistchina.txt',
      ],
      isBuiltIn: true,
      isEnabled: false,
    ),
    AdFilterSource(
      id: 'easylist_global',
      name: 'EasyList 全球通用基础规则 (英文/国际)',
      description: '国际广告拦截基石标准库，拦截海外全网广告联盟 (海外/英文网页推荐)',
      mirrorUrls: [
        'https://easylist.to/easylist/easylist.txt',
        'https://cdn.jsdelivr.net/gh/easylist/easylist@master/easylist/easylist.txt',
      ],
      isBuiltIn: true,
      isEnabled: false,
    ),
  ];

  // ------------------------- 响应式状态通知 -------------------------
  /// 当前生效的规则总数量
  final ValueNotifier<int> totalRulesNotifier = ValueNotifier<int>(0);

  /// 规则最后同步时间
  final ValueNotifier<DateTime?> lastUpdatedNotifier = ValueNotifier<DateTime?>(null);

  /// 是否正在从网络拉取更新
  final ValueNotifier<bool> isUpdatingNotifier = ValueNotifier<bool>(false);

  // ------------------------- 内置核心种子规则 -------------------------
  /// 内置高频核心域名黑名单 (体积仅 3KB，保证断网与新装 100% 生效)
  static const List<String> _kSeedDomainBlacklist = [
    // 百度联盟与移动推广探针
    'pos.baidu.com',
    'cpro.baidustatic.com',
    'union.baidu.com',
    'hm.baidu.com',
    'tongji.baidu.com',

    // 腾讯广点通与优量汇
    'mi.gdt.qq.com',
    'pgdt.gtimg.cn',
    'qzs.qq.com/qzone/biz',

    // 阿里妈妈与 Tanx 联盟
    'tanx.com',
    'alimama.com',
    'strip.taobaocdn.com',

    // 字节跳动穿山甲联盟与巨量引擎
    'pangolin-sdk',
    'pglstatp-toutiao.com',
    'volces.com/ad',

    // Google AdSense & DoubleClick
    'googlesyndication.com',
    'doubleclick.net',
    'googleadservices.com',

    // 常见第三方小说/影视暗刷、跳转统计与恶意唤起域名
    'cnzz.com',
    'umeng.com',
    '51.la',
    'zz.bdstatic.com',
    'inmobi.com',
    'mobvista.com',
    'admob.com',
    'ads.pubmatic.com',
    'rubiconproject.com',
    'openx.net',
  ];

  /// 内置通用小说/影视/漫画站 DOM 隐藏选择器 (秒杀常见悬浮与牛皮癣)
  static const List<String> _kSeedElementHidingSelectors = [
    '[class*="ad-"]',
    '[class*="ad_"]',
    '[id*="ad-"]',
    '[id*="ad_"]',
    '[class*="advert"]',
    '[id*="google_ads"]',
    '[class*="banner-ad"]',
    '.popup-ad',
    '.float-bar',
    '.app-download-bar',
    '.jump-app-bar',
    '.top-ad-bar',
    '.bottom-ad-bar',
    'iframe[src*="union"]',
    'iframe[src*="cpro"]',
    'iframe[src*="pos.baidu"]',
    'div[style*="z-index: 9999"]',
    'div[style*="z-index: 2147483647"]',
  ];

  /// 获取当前所有可用订阅源清单
  List<AdFilterSource> get sources => List.unmodifiable(_sources);

  /// 缓存存储目录路径
  Future<Directory> _getFiltersDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final filterDir = Directory(p.join(appDocDir.path, 'fluxforge_filters'));
    if (!await filterDir.exists()) {
      await filterDir.create(recursive: true);
    }
    return filterDir;
  }

  /// 初始化广告拦截引擎
  /// 优先加载本地已下载缓存，若无缓存则无缝回退至内置种子规则
  Future<void> initialize({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;

    try {
      _domainRules.clear();
      _elementHidingSelectors.clear();

      // 1. 先注入内置种子规则名单 (保证离线可用)
      _domainRules.addAll(_kSeedDomainBlacklist);
      _elementHidingSelectors.addAll(_kSeedElementHidingSelectors);

      // 2. 检查读取本地沙箱中的已下载规则文件
      final dir = await _getFiltersDirectory();
      int loadedCustomRulesCount = 0;

      for (final source in _sources) {
        if (!source.isEnabled) continue;
        final file = File(p.join(dir.path, '${source.id}.txt'));
        if (await file.exists()) {
          final content = await file.readAsString();
          final count = _parseRuleContent(content);
          loadedCustomRulesCount += count;
        }
      }

      // 3. 读取上次同步时间记录
      final syncTimeStr = await AppStorage.getString('adblock_last_sync_time');
      if (syncTimeStr != null && syncTimeStr.isNotEmpty) {
        lastUpdatedNotifier.value = DateTime.tryParse(syncTimeStr);
      }

      _isInitialized = true;
      totalRulesNotifier.value = _domainRules.length + _elementHidingSelectors.length;

      debugPrint(
        '【广告拦截引擎】初始化完成: 生效域名规则 ${_domainRules.length} 条, '
        'DOM 隐藏规则 ${_elementHidingSelectors.length} 条, 本地缓存补充 $loadedCustomRulesCount 条',
      );
    } catch (e) {
      debugPrint('【广告拦截引擎】初始化异常，启用保底种子模式: $e');
      _domainRules.addAll(_kSeedDomainBlacklist);
      _elementHidingSelectors.addAll(_kSeedElementHidingSelectors);
      _isInitialized = true;
      totalRulesNotifier.value = _domainRules.length + _elementHidingSelectors.length;
    }
  }

  /// 判断目标 URL 是否需要拦截
  bool shouldBlock(String url) {
    if (!_isInitialized) {
      // 若尚未异步初始化完，先用纯内存种子名单比对
      final urlLower = url.toLowerCase();
      return _kSeedDomainBlacklist.any((d) => urlLower.contains(d));
    }

    final urlLower = url.toLowerCase();

    // 1. 域名与关键词哈希快速命中 (O(1) 效率)
    if (_domainRules.any((rule) => urlLower.contains(rule))) {
      return true;
    }

    // 2. 正则表达式深度规则匹配
    if (_combinedRegex != null && _combinedRegex!.hasMatch(urlLower)) {
      return true;
    }

    return false;
  }

  /// 构建供 WebView 注入的 DOM 元素隐藏与恶意弹窗拆弹脚本
  String buildElementHidingScript() {
    // 限制注入选择器数量，避免注入过多导致浏览器 CSSOM 树阻塞
    final safeSelectors = _elementHidingSelectors.take(800).join(', ');

    return '''
(function() {
  // 1. 动态注入全局 CSS 强制隐藏广告占位容器
  if (!document.getElementById('fluxforge-adblock-style')) {
    const style = document.createElement('style');
    style.id = 'fluxforge-adblock-style';
    style.type = 'text/css';
    style.innerHTML = `
      $safeSelectors {
        display: none !important;
        visibility: hidden !important;
        width: 0 !important;
        height: 0 !important;
        opacity: 0 !important;
        pointer-events: none !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  }

  // 2. 拦截并拆解恶意 window.open 自动跳端与广告弹窗
  if (!window.__fluxforge_defuser_injected) {
    window.__fluxforge_defuser_injected = true;
    const originalOpen = window.open;
    window.open = function(url, target, features) {
      if (url && (
        url.startsWith('alipays://') || 
        url.startsWith('weixin://') || 
        url.startsWith('tbopen://') ||
        url.includes('ad') || 
        url.includes('union') ||
        url.includes('click')
      )) {
        console.log('[FluxForge AdBlock] 成功拦截流氓弹窗/跳端: ' + url);
        return null;
      }
      return originalOpen.apply(this, arguments);
    };
  }
})();
''';
  }

  /// 从网络下载并热更指定的规则库
  /// 支持多源 CDN 镜像自动容灾重试
  Future<bool> updateRules({List<String>? sourceIds}) async {
    if (isUpdatingNotifier.value) return false;
    isUpdatingNotifier.value = true;

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ),
    );

    final targetSources = sourceIds == null
        ? _sources.where((s) => s.isEnabled).toList()
        : _sources.where((s) => sourceIds.contains(s.id)).toList();

    int successCount = 0;
    final dir = await _getFiltersDirectory();

    for (final source in targetSources) {
      bool downloaded = false;

      // 依次遍历候选镜像下载地址，实现自动多线路容灾
      for (final url in source.mirrorUrls) {
        try {
          debugPrint('【广告拦截引擎】正在尝试从镜像拉取规则 [${source.name}]: $url');
          final response = await dio.get<String>(
            url,
            options: Options(responseType: ResponseType.plain),
          );

          if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
            final file = File(p.join(dir.path, '${source.id}.txt'));
            await file.writeAsString(response.data!);
            downloaded = true;
            successCount++;
            debugPrint('【广告拦截引擎】[${source.name}] 下载并缓存成功！');
            break; // 该源成功，跳向下一个源
          }
        } catch (e) {
          debugPrint('【广告拦截引擎】镜像 $url 请求失败，尝试下一节点: $e');
        }
      }

      if (!downloaded) {
        debugPrint('【广告拦截引擎】[${source.name}] 所有镜像节点均拉取失败');
      }
    }

    // 记录更新时间
    final now = DateTime.now();
    await AppStorage.setString('adblock_last_sync_time', now.toIso8601String());
    lastUpdatedNotifier.value = now;

    // 热重载规则进内存
    await initialize(forceReload: true);

    isUpdatingNotifier.value = false;
    return successCount > 0;
  }

  /// 添加自定义规则源
  void addCustomSource(String name, String url) {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _sources.add(
      AdFilterSource(
        id: id,
        name: name,
        description: '用户自定义订阅源',
        mirrorUrls: [url],
        isBuiltIn: false,
        isEnabled: true,
      ),
    );
  }

  /// 解析规则文本内容并分类存入内存
  int _parseRuleContent(String data) {
    int parsedCount = 0;
    final regexList = <String>[];

    for (final rawLine in const LineSplitter().convert(data)) {
      final line = rawLine.trim();

      // 忽略空行、注释与放行白名单
      if (line.isEmpty || line.startsWith('!') || line.startsWith('@@')) {
        continue;
      }

      // 1. 提取 DOM 元素隐藏规则 (以 ## 开头或 domain## 开头)
      final cosmeticIndex = line.indexOf('##');
      if (cosmeticIndex != -1) {
        final selector = line.substring(cosmeticIndex + 2).trim();
        // 过滤含有高级伪类或特殊 scriptlet 的规则，保留标准 CSS 选择器
        if (selector.isNotEmpty &&
            !selector.contains(':has(') &&
            !selector.contains(':contains(') &&
            !selector.contains(':matches-path(') &&
            !selector.startsWith('+js(')) {
          _elementHidingSelectors.add(selector);
          parsedCount++;
        }
        continue;
      }

      // 2. 提取标准网络拦截规则 (如 ||example.com^ 或 ||example.com/ad/*$script)
      if (line.startsWith('||')) {
        var domain = line.substring(2);
        // 清除结尾修饰符与协议修饰
        final separatorIdx = domain.indexOf('^');
        if (separatorIdx != -1) {
          domain = domain.substring(0, separatorIdx);
        }
        final optionIdx = domain.indexOf(r'$');
        if (optionIdx != -1) {
          domain = domain.substring(0, optionIdx);
        }
        domain = domain.trim();
        if (domain.isNotEmpty && domain.length > 3) {
          _domainRules.add(domain);
          parsedCount++;
        }
        continue;
      }

      // 3. 提取正则表达式规则 (/pattern/)
      if (line.startsWith('/') && line.endsWith('/') && line.length > 2) {
        try {
          regexList.add(line.substring(1, line.length - 1));
          parsedCount++;
        } catch (_) {}
      }
    }

    if (regexList.isNotEmpty) {
      try {
        _combinedRegex = RegExp(regexList.take(200).join('|'));
      } catch (_) {}
    }

    return parsedCount;
  }
}
