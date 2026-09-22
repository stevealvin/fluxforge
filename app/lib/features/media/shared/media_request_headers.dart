import 'package:fluxforge/core/network/api_client.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';

/// 媒体资源请求头的统一兜底（封面 / 正文配图 / 漫画图 / 播放直链 / 离线下载共用）
///
/// ### 为什么需要它
/// 同一份「规则请求头」其实经**两条完全不同的通道**发出：
///
/// 1. **规则页请求** → 走 `RuleEngine` 的桥接层，UA 缺省时由引擎自动注入；
/// 2. **图片 / 视频直链** → 由 `ExtendedImage` / 播放器**直连**，引擎完全管不着。
///
/// 于是出现一种很迷惑的现象：站点只校验第 1 条通道时一切正常（**发现页能出图**），
/// 而资源一旦走第 2 条通道又缺 UA / Referer，防盗链直接回 **403**
/// （**进详情页图全挂**）。发现页之所以正常，正是因为它自己带了
/// `referer` + `user-agent`；详情页只注入了 Referer。
///
/// 本函数是**纯函数**：不改动入参、**不覆盖已有键**（大小写不敏感），只补齐缺失项，
/// 因此对已经跑通的路径（如带自定义 UA 的规则）零影响。
class MediaRequestHeaders {
  MediaRequestHeaders._();

  /// 补齐防盗链所需的默认头；[headers] 中已声明的键一律保留
  ///
  /// - [referer]：仅当 [headers] 里没有 `referer` / `Referer` 时写入；
  /// - [userAgent]：缺省用 [defaultUserAgent]（即应用当前生效的 UA）。
  static Map<String, String> withDefaults(
    Map<String, String> headers, {
    String referer = '',
    String? userAgent,
  }) {
    final result = Map<String, String>.from(headers);

    if (referer.isNotEmpty && !_has(result, 'referer')) {
      result['Referer'] = referer;
    }

    if (!_has(result, 'user-agent')) {
      final ua = (userAgent ?? defaultUserAgent).trim();
      if (ua.isNotEmpty) result['User-Agent'] = ua;
    }

    return result;
  }

  /// 直链资源（封面 / 正文配图 / 漫画图 / 播放直链）的 Referer 兜底取值
  ///
  /// 顺序：**规则 baseUrl（站点根）→ 页面地址的站点根 → 页面地址本身**。
  ///
  /// 「站点根优先」是关键：直链由 `ExtendedImage` / 播放器**直连**，图床与 CDN
  /// 校验 Referer 时通常只认站点根；而详情页 URL 是规则内部的页面 / 接口地址
  /// （可能是深层路径、甚至 API 地址），会被判成盗链而回 **403**。
  /// 已有实测：`curl -H "Referer: <站点根>"` 可下载，发现页用的是同一个值所以一直正常。
  static String resolveReferer({String? ruleBaseUrl, String pageUrl = ''}) {
    final baseUrl = ruleBaseUrl?.trim() ?? '';
    if (baseUrl.isNotEmpty) return baseUrl;

    final url = pageUrl.trim();
    if (url.isEmpty) return '';

    // 无 baseUrl 时退到页面地址的站点根，仍优于直接把深层地址当 Referer
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return '${uri.scheme}://${uri.host}';
    }
    return url;
  }

  /// 应用当前生效的 User-Agent（用户在设置里自定义过即用自定义值）
  ///
  /// 与规则页请求同源：引擎给 XHR 注入的也是这一个，避免同一次阅读里
  /// 「页面用 UA-A、图片用 UA-B」这种自相矛盾的指纹。
  static String get defaultUserAgent {
    try {
      final configured = RuleEngine.currentUserAgent.trim();
      if (configured.isNotEmpty) return configured;
    } catch (_) {
      // 依赖未就绪（纯组件 / 单测环境）→ 回退内置默认值，不影响渲染
    }
    return ApiClient.defaultUserAgent;
  }

  static bool _has(Map<String, String> headers, String name) =>
      headers.keys.any((k) => k.toLowerCase() == name);
}
