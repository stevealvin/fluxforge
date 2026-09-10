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

  /// 域名匹配黑名单 (Set 结构哈希加速，O(1) 查询)
  final Set<String> _blockedDomains = {};

  /// 域名放行白名单 (@@||domain^ 等)
  final Set<String> _whitelistDomains = {};

  /// URL 关键词与路径拦截规则库 (如 ||example.com/ad/*)
  final Set<String> _blockedUrlPatterns = {};

  /// 正则匹配深度规则
  final List<RegExp> _regexRules = [];

  /// 通用元素隐藏 CSS 选择器 (##.selector)
  final Set<String> _genericCosmeticRules = {};

  /// 域名限定元素隐藏 CSS 选择器映射 (domain##.selector)
  /// key: 域名 (如 "bilibili.com")，value: 该域名下的专用选择器集合
  final Map<String, Set<String>> _domainCosmeticRules = {};

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
  /// 订阅源列表变更通知
  late final ValueNotifier<List<AdFilterSource>> sourcesNotifier =
      ValueNotifier<List<AdFilterSource>>(List.unmodifiable(_sources));

  /// 当前生效的规则总数量
  final ValueNotifier<int> totalRulesNotifier = ValueNotifier<int>(0);

  /// 规则最后同步时间
  final ValueNotifier<DateTime?> lastUpdatedNotifier = ValueNotifier<DateTime?>(null);

  /// 是否正在从网络拉取更新
  final ValueNotifier<bool> isUpdatingNotifier = ValueNotifier<bool>(false);

  // ------------------------- 内置核心种子规则 -------------------------
  /// 内置高频核心域名黑名单 (覆盖全网主流联盟、暗刷探针与诱导跳转，保证断网与新装 100% 生效)
  static const List<String> _kSeedDomainBlacklist = [
    // 百度联盟与移动推广探针
    'pos.baidu.com',
    'cpro.baidustatic.com',
    'union.baidu.com',
    'hm.baidu.com',
    'tongji.baidu.com',
    'mobads.baidu.com',
    'bzclk.baidu.com',

    // 腾讯广点通与优量汇
    'mi.gdt.qq.com',
    'pgdt.gtimg.cn',
    'qzs.qq.com/qzone/biz',
    'tmead.y.qq.com',
    'adnet.qq.com',

    // 阿里妈妈与 Tanx 联盟
    'tanx.com',
    'alimama.com',
    'strip.taobaocdn.com',
    'atanx.alicdn.com',
    'click.tanx.com',

    // 字节跳动穿山甲联盟与巨量引擎
    'pangolin-sdk',
    'pglstatp-toutiao.com',
    'volces.com/ad',
    'toblog.ctobsnssdk.com',
    'pangolin.snssdk.com',
    'ad.toutiao.com',

    // Google AdSense & DoubleClick
    'googlesyndication.com',
    'doubleclick.net',
    'googleadservices.com',
    '2mdn.net',
    'googletagmanager.com',
    'googletagservices.com',

    // 常见统计探针、小说/影视暗刷与恶意唤起域名
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
    'criteo.com',
    'taboola.com',
    'outbrain.com',
    'applovin.com',
    'vungle.com',
    'mintegral.com',
    'unityads.unity3d.com',
    'scorecardresearch.com',
    'amazon-adsystem.com',
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
    'iframe[src*="tanx"]',
    'iframe[src*="doubleclick"]',
    'iframe[src*="googlesyndication"]',
    '.adsbygoogle',
    '[class*="float-ad"]',
    '[id*="float-ad"]',
    '.ad-wrapper',
    '.ad-container',
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

  /// 持久化订阅源启停配置与自定义订阅列表
  Future<void> _saveSourcesState() async {
    try {
      final customSources = _sources.where((s) => !s.isBuiltIn).map((s) => s.toJson()).toList();
      final enabledMap = {for (final s in _sources) s.id: s.isEnabled};
      final payload = jsonEncode({
        'enabledMap': enabledMap,
        'customSources': customSources,
      });
      await AppStorage.setString('adblock_sources_config', payload);
    } catch (e) {
      debugPrint('【广告拦截引擎】保存订阅源配置失败: $e');
    }
  }

  /// 从存储中恢复订阅源配置
  Future<void> _loadSourcesState() async {
    final raw = await AppStorage.getString('adblock_sources_config');
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final enabledMap = (data['enabledMap'] as Map<String, dynamic>?)?.cast<String, dynamic>();
      if (enabledMap != null) {
        for (final s in _sources) {
          if (enabledMap.containsKey(s.id)) {
            s.isEnabled = enabledMap[s.id] as bool? ?? s.isEnabled;
          }
        }
      }
      final customList = (data['customSources'] as List<dynamic>?) ?? [];
      for (final item in customList) {
        final parsed = AdFilterSource.fromJson(Map<String, dynamic>.from(item as Map));
        if (!_sources.any((s) => s.id == parsed.id)) {
          _sources.add(parsed);
        }
      }
      sourcesNotifier.value = List.unmodifiable(_sources);
    } catch (e) {
      debugPrint('【广告拦截引擎】加载持久化订阅源失败: $e');
    }
  }

  /// 初始化广告拦截引擎
  /// 优先加载本地已下载缓存并建立索引，若无缓存则快速启用内置保底种子
  Future<void> initialize({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;

    try {
      await _loadSourcesState();

      _blockedDomains.clear();
      _whitelistDomains.clear();
      _blockedUrlPatterns.clear();
      _regexRules.clear();
      _genericCosmeticRules.clear();
      _domainCosmeticRules.clear();

      // 1. 先注入内置种子规则名单 (保证离线可用)
      _blockedDomains.addAll(_kSeedDomainBlacklist);
      _genericCosmeticRules.addAll(_kSeedElementHidingSelectors);

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
      _updateTotalRulesCount();
      sourcesNotifier.value = List.unmodifiable(_sources);

      debugPrint(
        '【广告拦截引擎】初始化完成: 拦截域名 ${_blockedDomains.length} 个, '
        '通用隐藏规则 ${_genericCosmeticRules.length} 条, '
        '专属域名规则 ${_domainCosmeticRules.length} 站, 本地缓存补充 $loadedCustomRulesCount 条',
      );

      // 4. 若为新安装无本地缓存文件，在后台静默触发拉取最新规则（不阻塞 UI）
      if (loadedCustomRulesCount == 0 && !isUpdatingNotifier.value) {
        Future.delayed(const Duration(seconds: 2), () {
          updateRules();
        });
      }
    } catch (e) {
      debugPrint('【广告拦截引擎】初始化异常，启用保底种子模式: $e');
      _blockedDomains.addAll(_kSeedDomainBlacklist);
      _genericCosmeticRules.addAll(_kSeedElementHidingSelectors);
      _isInitialized = true;
      _updateTotalRulesCount();
    }
  }

  void _updateTotalRulesCount() {
    int domainRulesCount = 0;
    for (final set in _domainCosmeticRules.values) {
      domainRulesCount += set.length;
    }
    totalRulesNotifier.value = _blockedDomains.length +
        _blockedUrlPatterns.length +
        _genericCosmeticRules.length +
        domainRulesCount +
        _regexRules.length;
  }

  /// 判断目标 URL 是否需要阻断 (支持白名单放行、域名后缀回溯、路径关键词与正则)
  bool shouldBlock(String url) {
    if (url.isEmpty ||
        url.startsWith('data:') ||
        url.startsWith('blob:') ||
        url.startsWith('about:')) {
      return false;
    }

    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';

    // 1. 白名单放行检查
    if (host.isNotEmpty && _matchesDomain(host, _whitelistDomains)) {
      return false;
    }

    // 2. 域名哈希快速匹配 (O(1) 效率，向上逐级回溯)
    if (host.isNotEmpty && _matchesDomain(host, _blockedDomains)) {
      return true;
    }

    // 尚未初始化完毕时的保底快速比对
    if (!_isInitialized) {
      if (host.isNotEmpty && _matchesDomain(host, _kSeedDomainBlacklist.toSet())) {
        return true;
      }
    }

    final urlLower = url.toLowerCase();

    // 3. URL 路径与关键词匹配
    for (final pattern in _blockedUrlPatterns) {
      if (urlLower.contains(pattern)) {
        return true;
      }
    }

    // 4. 正则表达式深度规则匹配
    for (final regex in _regexRules) {
      if (regex.hasMatch(urlLower)) {
        return true;
      }
    }

    return false;
  }

  /// 域名后缀逐级向上回溯匹配算法
  /// 例如输入 a.pos.baidu.com，依次检查 a.pos.baidu.com -> pos.baidu.com -> baidu.com
  bool _matchesDomain(String host, Set<String> domainSet) {
    if (host.isEmpty) return false;
    var cur = host;
    while (cur.isNotEmpty) {
      if (domainSet.contains(cur)) return true;
      final dotIdx = cur.indexOf('.');
      if (dotIdx == -1) break;
      cur = cur.substring(dotIdx + 1);
    }
    return false;
  }

  /// 根据当前访问的目标页面 URL，解析出专属生效的 CSS 隐藏选择器
  List<String> getCosmeticSelectorsForUrl(String pageUrl) {
    final uri = Uri.tryParse(pageUrl);
    final host = uri?.host.toLowerCase() ?? '';

    final matched = <String>{};

    // 1. 提取当前域名及上级域名所关联的特化选择器 (如 bilibili.com##.ad)
    if (host.isNotEmpty) {
      var cur = host;
      while (cur.isNotEmpty) {
        final domainSelectors = _domainCosmeticRules[cur];
        if (domainSelectors != null) {
          matched.addAll(domainSelectors);
        }
        final dotIdx = cur.indexOf('.');
        if (dotIdx == -1) break;
        cur = cur.substring(dotIdx + 1);
      }
    }

    // 2. 提取全局通用隐藏选择器 (限制前 400 条，保证注入速度与 CSSOM 渲染效率)
    matched.addAll(_genericCosmeticRules.take(400));

    // 3. 补充保底高频选择器
    matched.addAll(_kSeedElementHidingSelectors);

    return matched.toList();
  }

  /// 构建供 WebView 注入的专属 Content Script (对标 AdBlock Plus / uBlock Origin 插件 Content Script)
  String buildContentScriptForUrl(String pageUrl) {
    final relevantSelectors = getCosmeticSelectorsForUrl(pageUrl);

    // 提取高频域名阻断子集 (前 1500 条) 与关键词 (前 200 条) 注入 JS 内存快速 Set
    final highFreqDomains = <String>{};
    highFreqDomains.addAll(_kSeedDomainBlacklist);
    highFreqDomains.addAll(_blockedDomains.take(1500));

    final highFreqPatterns = _blockedUrlPatterns.take(200).toList();

    final jsonDomains = jsonEncode(highFreqDomains.toList());
    final jsonKeywords = jsonEncode(highFreqPatterns);
    final jsonSelectors = jsonEncode(relevantSelectors);

    return '''
(function() {
  if (window.__fluxforge_adblock_installed) return;
  window.__fluxforge_adblock_installed = true;

  const BLOCKED_DOMAINS = new Set($jsonDomains);
  const BLOCKED_KEYWORDS = $jsonKeywords;
  const COSMETIC_SELECTORS = $jsonSelectors;

  function extractHost(url) {
    try {
      if (!url || typeof url !== 'string') return '';
      if (url.startsWith('//')) url = window.location.protocol + url;
      if (url.startsWith('/')) return window.location.hostname.toLowerCase();
      const a = document.createElement('a');
      a.href = url;
      return (a.hostname || '').toLowerCase();
    } catch(e) {
      return '';
    }
  }

  function isDomainBlocked(host) {
    if (!host) return false;
    let cur = host;
    while (cur) {
      if (BLOCKED_DOMAINS.has(cur)) return true;
      const dot = cur.indexOf('.');
      if (dot === -1) break;
      cur = cur.substring(dot + 1);
    }
    return false;
  }

  function shouldBlockUrl(url) {
    if (!url || typeof url !== 'string') return false;
    if (url.startsWith('data:') || url.startsWith('blob:') || url.startsWith('about:')) return false;
    const host = extractHost(url);
    if (isDomainBlocked(host)) return true;
    const lower = url.toLowerCase();
    for (let i = 0; i < BLOCKED_KEYWORDS.length; i++) {
      if (lower.indexOf(BLOCKED_KEYWORDS[i]) !== -1) return true;
    }
    return false;
  }

  // 1. 网络层全覆盖拦截 Hook (对标 AdBlock 插件 webRequest API)
  try {
    const origFetch = window.fetch;
    window.fetch = function(input, init) {
      const url = typeof input === 'string' ? input : (input && input.url ? input.url : '');
      if (url && shouldBlockUrl(url)) {
        console.log('[FluxForge AdBlock] 成功拦截 Fetch 广告请求:', url);
        return Promise.reject(new TypeError('Blocked by FluxForge AdBlock'));
      }
      return origFetch.apply(this, arguments);
    };
  } catch(e) {}

  try {
    const origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__flux_blocked = url && shouldBlockUrl(url);
      if (this.__flux_blocked) {
        console.log('[FluxForge AdBlock] 成功拦截 XHR 广告请求:', url);
      }
      return origOpen.apply(this, arguments);
    };
    const origSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function() {
      if (this.__flux_blocked) {
        this.abort();
        return;
      }
      return origSend.apply(this, arguments);
    };
  } catch(e) {}

  try {
    const scriptDesc = Object.getOwnPropertyDescriptor(HTMLScriptElement.prototype, 'src');
    if (scriptDesc && scriptDesc.set) {
      const origScriptSet = scriptDesc.set;
      Object.defineProperty(HTMLScriptElement.prototype, 'src', {
        set: function(val) {
          if (val && shouldBlockUrl(val)) {
            console.log('[FluxForge AdBlock] 成功拦截 Script 广告标签:', val);
            this.setAttribute('data-flux-adblock', 'blocked');
            return origScriptSet.call(this, 'data:text/javascript;void(0);');
          }
          return origScriptSet.call(this, val);
        },
        get: scriptDesc.get,
        configurable: true,
        enumerable: true
      });
    }
  } catch(e) {}

  try {
    const iframeDesc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'src');
    if (iframeDesc && iframeDesc.set) {
      const origIframeSet = iframeDesc.set;
      Object.defineProperty(HTMLIFrameElement.prototype, 'src', {
        set: function(val) {
          if (val && shouldBlockUrl(val)) {
            console.log('[FluxForge AdBlock] 成功拦截 IFrame 广告:', val);
            this.setAttribute('data-flux-adblock', 'blocked');
            return origIframeSet.call(this, 'about:blank');
          }
          return origIframeSet.call(this, val);
        },
        get: iframeDesc.get,
        configurable: true,
        enumerable: true
      });
    }
  } catch(e) {}

  try {
    const imgDesc = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
    if (imgDesc && imgDesc.set) {
      const origImgSet = imgDesc.set;
      Object.defineProperty(HTMLImageElement.prototype, 'src', {
        set: function(val) {
          if (val && shouldBlockUrl(val)) {
            return origImgSet.call(this, 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7');
          }
          return origImgSet.call(this, val);
        },
        get: imgDesc.get,
        configurable: true,
        enumerable: true
      });
    }
  } catch(e) {}

  // 2. 容错式 CSS 元素隐藏注入 (对标 uBlock Origin Cosmetic Filtering)
  function applyCosmeticFilters() {
    let style = document.getElementById('fluxforge-adblock-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'fluxforge-adblock-style';
      (document.head || document.documentElement).appendChild(style);
    }
    const sheet = style.sheet;
    if (!sheet) return;

    for (let i = 0; i < COSMETIC_SELECTORS.length; i++) {
      try {
        const rule = COSMETIC_SELECTORS[i] + ' { display: none !important; visibility: hidden !important; width: 0 !important; height: 0 !important; pointer-events: none !important; }';
        sheet.insertRule(rule, sheet.cssRules.length);
      } catch(e) {}
    }
  }

  // 3. 动态 DOM 监听与牛皮癣悬浮清理 (MutationObserver)
  function scanAndClean(root) {
    if (!root || !root.querySelectorAll) return;
    try {
      const frames = root.querySelectorAll('iframe, embed, object');
      for (let i = 0; i < frames.length; i++) {
        const f = frames[i];
        if (f.src && shouldBlockUrl(f.src)) {
          f.remove();
        }
      }

      const scripts = root.querySelectorAll('script[src]');
      for (let i = 0; i < scripts.length; i++) {
        const s = scripts[i];
        if (s.src && shouldBlockUrl(s.src)) {
          s.remove();
        }
      }

      const fixedEls = root.querySelectorAll('div, section, aside');
      for (let i = 0; i < fixedEls.length; i++) {
        const el = fixedEls[i];
        const st = window.getComputedStyle ? window.getComputedStyle(el) : null;
        if (st && (st.position === 'fixed' || st.position === 'sticky')) {
          const zIndex = parseInt(st.zIndex, 10);
          if (zIndex >= 9999) {
            const txt = (el.innerText || '').trim();
            if (txt.includes('下载APP') || txt.includes('打开APP') || txt.includes('立即下载') || txt.includes('点击查看') || txt.includes('广告')) {
              el.style.setProperty('display', 'none', 'important');
            }
          }
        }
      }
    } catch(e) {}
  }

  // 4. 恶意弹窗与外链跳端转由客户端提示用户确认 (window.open Hook)
  try {
    const origOpen = window.open;
    window.open = function(url, target, features) {
      if (url && typeof url === 'string') {
        const isExternalScheme = !url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('about:') && !url.startsWith('data:') && !url.startsWith('blob:');
        if (isExternalScheme || shouldBlockUrl(url)) {
          if (window.FluxExternalLinkChannel) {
            window.FluxExternalLinkChannel.postMessage(url);
            return null;
          }
        }
      }
      return origOpen.apply(this, arguments);
    };
  } catch(e) {}

  // 挂载初次注入与监听
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
      applyCosmeticFilters();
      scanAndClean(document.body);
    });
  } else {
    applyCosmeticFilters();
    scanAndClean(document.body);
  }

  try {
    const observer = new MutationObserver(function(mutations) {
      for (let i = 0; i < mutations.length; i++) {
        const mut = mutations[i];
        for (let j = 0; j < mut.addedNodes.length; j++) {
          const node = mut.addedNodes[j];
          if (node.nodeType === 1) {
            scanAndClean(node);
          }
        }
      }
    });
    observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
  } catch(e) {}
})();
''';
  }

  /// 兼容旧版调用
  String buildElementHidingScript([String? url]) {
    return buildContentScriptForUrl(url ?? '');
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

  /// 添加自定义规则源并持久化
  Future<bool> addCustomSource(String name, String url) async {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final newSource = AdFilterSource(
      id: id,
      name: name.trim(),
      description: '用户自定义订阅源',
      mirrorUrls: [url.trim()],
      isBuiltIn: false,
      isEnabled: true,
    );
    _sources.add(newSource);
    sourcesNotifier.value = List.unmodifiable(_sources);
    await _saveSourcesState();
    // 立即拉取并编译该自定义源
    final success = await updateRules(sourceIds: [id]);
    return success;
  }

  /// 启停指定订阅源
  Future<void> toggleSource(String id, bool enabled) async {
    final idx = _sources.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _sources[idx].isEnabled = enabled;
      sourcesNotifier.value = List.unmodifiable(_sources);
      await _saveSourcesState();
      await initialize(forceReload: true);
    }
  }

  /// 删除自定义订阅源
  Future<void> deleteCustomSource(String id) async {
    _sources.removeWhere((s) => s.id == id && !s.isBuiltIn);
    sourcesNotifier.value = List.unmodifiable(_sources);
    await _saveSourcesState();
    try {
      final dir = await _getFiltersDirectory();
      final file = File(p.join(dir.path, '$id.txt'));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    await initialize(forceReload: true);
  }

  /// 对单个订阅源进行独立更新
  Future<bool> updateSingleSource(String id) async {
    return await updateRules(sourceIds: [id]);
  }

  /// 解析标准 ABP / AdGuard 规则文本内容并分类存入内存索引
  int _parseRuleContent(String data) {
    int parsedCount = 0;
    final regexList = <String>[];

    for (final rawLine in const LineSplitter().convert(data)) {
      final line = rawLine.trim();

      // 忽略空行、注释与文件头
      if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) {
        continue;
      }

      // 1. 白名单规则提取 (@@||domain^ 或 @@||domain)
      if (line.startsWith('@@')) {
        var rule = line.substring(2);
        if (rule.startsWith('||')) rule = rule.substring(2);
        final optIdx = rule.indexOf(r'$');
        if (optIdx != -1) rule = rule.substring(0, optIdx);
        final sepIdx = rule.indexOf('^');
        if (sepIdx != -1) rule = rule.substring(0, sepIdx);
        rule = rule.trim().toLowerCase();
        if (rule.isNotEmpty) {
          _whitelistDomains.add(rule);
          parsedCount++;
        }
        continue;
      }

      // 2. DOM 元素隐藏规则 (以 ## 开头或 domain1,domain2## 开头)
      final cosmeticIndex = line.indexOf('##');
      if (cosmeticIndex != -1) {
        final domainPart = line.substring(0, cosmeticIndex).trim();
        final selector = line.substring(cosmeticIndex + 2).trim();

        // 过滤含有扩展 scriptlet、不规范选择器 (+js, :has, :contains, etc.)
        if (selector.isEmpty ||
            selector.startsWith('+js(') ||
            selector.contains(':contains(') ||
            selector.contains(':has(') ||
            selector.contains(':matches-path(')) {
          continue;
        }

        if (domainPart.isEmpty) {
          // 通用隐藏规则 (如 ##.adsbygoogle)
          _genericCosmeticRules.add(selector);
        } else {
          // 域名限定规则 (如 bilibili.com,iqiyi.com##.vip-ad-box)
          final domains = domainPart.split(',');
          for (final d in domains) {
            final cleanD = d.trim().toLowerCase();
            if (cleanD.isNotEmpty && !cleanD.startsWith('~')) {
              _domainCosmeticRules.putIfAbsent(cleanD, () => <String>{}).add(selector);
            }
          }
        }
        parsedCount++;
        continue;
      }

      // 3. 标准网络拦截规则 (||domain.com^ 或 ||domain.com/ad/*$script)
      if (line.startsWith('||')) {
        var domain = line.substring(2);
        final optionIdx = domain.indexOf(r'$');
        if (optionIdx != -1) {
          domain = domain.substring(0, optionIdx);
        }
        final separatorIdx = domain.indexOf('^');
        if (separatorIdx != -1) {
          domain = domain.substring(0, separatorIdx);
        }
        domain = domain.trim().toLowerCase();
        if (domain.isNotEmpty && domain.length > 2) {
          if (domain.contains('/')) {
            _blockedUrlPatterns.add(domain);
          } else {
            _blockedDomains.add(domain);
          }
          parsedCount++;
        }
        continue;
      }

      // 4. 精确前缀网络拦截规则 (|http...)
      if (line.startsWith('|http')) {
        var pattern = line.substring(1);
        final optIdx = pattern.indexOf(r'$');
        if (optIdx != -1) pattern = pattern.substring(0, optIdx);
        final sepIdx = pattern.indexOf('^');
        if (sepIdx != -1) pattern = pattern.substring(0, sepIdx);
        pattern = pattern.trim().toLowerCase();
        if (pattern.length > 6) {
          _blockedUrlPatterns.add(pattern);
          parsedCount++;
        }
        continue;
      }

      // 5. 正则表达式深度匹配规则 (/pattern/)
      if (line.startsWith('/') && line.endsWith('/') && line.length > 2) {
        try {
          regexList.add(line.substring(1, line.length - 1));
          parsedCount++;
        } catch (_) {}
      }
    }

    if (regexList.isNotEmpty) {
      try {
        _regexRules.add(RegExp(regexList.take(200).join('|')));
      } catch (_) {}
    }

    return parsedCount;
  }
}
