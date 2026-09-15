import 'dart:async';
import 'dart:convert';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quickjs_engine/quickjs_engine.dart';
import '../core/utils/app_logger.dart';
import '../models/rule.dart';
import 'app_service.dart';
import 'di.dart';

/// FluxForge 本地高性能 JavaScript 沙箱执行引擎 (基于 QuickJS-NG 0.14.0)
/// 负责注入 axios、cheerio 与 Node.js 兼容环境，调度执行规则的 discovery、search、detail、parse 生命周期
/// 全平台（Android, iOS, macOS, Windows, Linux）统一现代化 QuickJS-NG 引擎内核，原生支持 ES2020+ 与异步 Promise
/// 内置 console.log 拦截器与 Dio 原生安全 HTTP 适配器，关闭引擎自带存在反引号截断缺陷的 XHR，实现零挂起高并发
class RuleEngine {
  // 采用现代 QuickJS-NG 内核，显式指定 xhr: false 关闭自带旧 XHR，全面由自研 Dio 原生安全网络通道接管
  static final JavascriptRuntime _jsRuntime = getJavascriptRuntime(xhr: false);
  static bool _initialized = false;

  /// 原生高性能网络请求客户端，专为 JS 沙箱提供底层通信服务
  /// 彻底替代 flutter_js 内置由于模板字符串拼接缺陷导致的反引号语法崩溃与超时
  static final Dio _nativeDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 5,
    ),
  );

  /// 规则沙箱网络持久化 Cookie 容器 (自动维护 Set-Cookie 与请求头携带)
  static CookieJar? _cookieJar;

  /// 获取当前 CookieJar 实例 (若未进行磁盘初始化，降级使用内存 CookieJar 保证零异常)
  static CookieJar get cookieJar {
    if (_cookieJar == null) {
      _cookieJar = CookieJar();
      _attachCookieManager(_cookieJar!);
    }
    return _cookieJar!;
  }

  /// 挂载 CookieManager 拦截器到 _nativeDio (防重复挂载)
  static void _attachCookieManager(CookieJar jar) {
    if (!_nativeDio.interceptors.any((i) => i is CookieManager)) {
      _nativeDio.interceptors.add(CookieManager(jar));
    }
  }

  /// 清空规则沙箱及原生网络请求存储的所有 Cookie 缓存 (使用 getter 保证未初始化时也能准确定位并清空)
  static Future<void> clearCookies() async {
    await cookieJar.deleteAll();
  }

  /// 缓存初始化 Future，避免并发调用时重复执行初始化流程
  static Future<void>? _initFuture;

  /// 当前正在沙箱中执行的规则名称（用于关联 console.log 打印来源）
  static String _currentRunningRuleName = 'Sandbox';

  /// 获取当前配置的沙箱超时秒数（优先读取 AppSettings，降级为默认 30 秒）
  static int get defaultTimeoutSeconds {
    if (getIt.isRegistered<AppService>()) {
      return appService.settingsNotifier.value.requestTimeoutSeconds;
    }
    return 30;
  }

  /// 获取当前配置的 User-Agent
  static String get currentUserAgent {
    if (getIt.isRegistered<AppService>()) {
      final custom = appService.settingsNotifier.value.customUserAgent.trim();
      if (custom.isNotEmpty) return custom;
    }
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
  }

  /// 初始化运行环境与注入核心依赖
  static Future<void> init() {
    if (_initialized) return Future<void>.value();
    // 并发调用共享同一次初始化流程，避免重复执行 evaluate 加载运行库
    return _initFuture ??= _doInit();
  }

  /// 实际初始化实现（内部方法，请统一通过 init() 调用以复用并发任务）
  static Future<void> _doInit() async {
    try {
      final defaultTimeout = defaultTimeoutSeconds;
      final defaultUa = currentUserAgent;
      final encodedUa = jsonEncode(defaultUa);

      // 0. 初始化规则网络持久化 Cookie 存储（按应用文档目录持久化保存，保证应用重启后登录态与会话不丢失）
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final persistJar = PersistCookieJar(
          storage: FileStorage('${docDir.path}/.cookies'),
        );
        _cookieJar = persistJar;
        // 替换为持久化拦截器
        _nativeDio.interceptors.removeWhere((i) => i is CookieManager);
        _nativeDio.interceptors.add(CookieManager(persistJar));
      } catch (e) {
        // 单元测试或无原生文件权限环境安全降级为内存 CookieJar
        if (_cookieJar == null) {
          _cookieJar = CookieJar();
          _attachCookieManager(_cookieJar!);
        }
      }

      // 1. 基础全局环境注入
      _jsRuntime.evaluate('''
        var window = global = globalThis;
        var ua = $encodedUa;
        var module = { exports: {} };
        var exports = module.exports;
        // 关键沙箱环境支持：注入 defineRule 规则声明包裹器，自动挂载到当前模块导出中
        var defineRule = function(r) {
          if (r && typeof r === 'object') {
            if (globalThis.module) globalThis.module.exports = r;
            globalThis._fluxLastDefinedRule = r;
          }
          return r;
        };
        var require = function(name) {
          if (name === 'axios') return axios;
          if (name === 'cheerio') return cheerio;
          return {};
        };
      ''');

      // 2. 注入增强型 console 代理并注册 ConsoleLog 跨桥监听
      _setupEnhancedConsole();

      // 3. 加载内置 JS 运行库 (标准 Web API polyfill, axios 与 cheerio)
      // 注意：evaluate 是主 isolate 上的同步 FFI 调用，cheerio.js 体积约 380KB，
      // 连续加载会长时间占用主线程导致 UI 掉帧，因此每个库之间主动让出一次事件循环。
      await _loadJSFile('assets/js/url.polyfill.js');
      await Future<void>.delayed(Duration.zero);
      await _loadJSFile('assets/js/axios.min.js');
      await Future<void>.delayed(Duration.zero);
      await _loadJSFile('assets/js/cheerio.js');
      await Future<void>.delayed(Duration.zero);

      _jsRuntime.evaluate('''
        if (typeof axios !== 'undefined' && axios.defaults) {
          if (axios.defaults.headers) {
            axios.defaults.headers.common['User-Agent'] = ua;
          }
          axios.defaults.timeout = ${defaultTimeout * 1000};
        }
      ''');

      // 4. 注册原生安全高性能 HTTP 适配器 (基于 Dio + jsonEncode，彻底杜绝反引号截断与挂起假死)
      _setupNativeHttpBridge();

      _initialized = true;
      AppLogger.addLog(
        level: 'INFO',
        tag: 'Rule Sandbox',
        message: 'QuickJS-NG 沙箱内核初始化就绪 (Node.js 兼容层/Axios/Cheerio/Dio原生通道已加载)',
      );
    } catch (e, stack) {
      debugPrint('RuleEngine init error: $e');
      AppLogger.addLog(
        level: 'ERROR',
        tag: 'Rule Sandbox',
        message: 'QuickJS 沙箱初始化失败: $e',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// 统一处理从 JS 沙箱回传的 console 日志并安全打入 AppLogger
  static void _handleConsoleLog(dynamic args) {
    try {
      String level = 'INFO';
      String message = '';

      if (args is List) {
        if (args.isNotEmpty) {
          final first = args[0]?.toString().toUpperCase() ?? 'INFO';
          if (first == 'LOG' || first == 'INFO' || first == 'WARN' || first == 'WARNING' || first == 'ERROR' || first == 'DEBUG') {
            level = first == 'LOG' ? 'INFO' : first;
            message = args.length > 1 ? args.sublist(1).map((e) => e?.toString() ?? '').join(' ') : '';
          } else {
            message = args.map((e) => e?.toString() ?? '').join(' ');
          }
        }
      } else if (args is Map) {
        level = args['level']?.toString().toUpperCase() ?? 'INFO';
        message = args['message']?.toString() ?? args.toString();
      } else if (args is String) {
        try {
          final decoded = jsonDecode(args);
          if (decoded is List) {
            _handleConsoleLog(decoded);
            return;
          }
        } catch (_) {}
        message = args;
      } else {
        message = args?.toString() ?? '';
      }

      final tag = _currentRunningRuleName.isNotEmpty
          ? 'Rule: $_currentRunningRuleName'
          : 'Rule Sandbox';

      AppLogger.addLog(
        level: level,
        tag: tag,
        message: message,
      );
      debugPrint('[$tag][$level] $message');
    } catch (e) {
      debugPrint('[RuleEngine] ConsoleLog dispatch error: $e');
    }
  }

  @visibleForTesting
  static void setCurrentRunningRuleNameForTest(String name) {
    _currentRunningRuleName = name;
  }

  @visibleForTesting
  static void handleConsoleLogForTest(dynamic args) {
    _handleConsoleLog(args);
  }

  /// 注入强化版 console 代理，捕获规则内的 log/info/warn/error/debug 并转发到 AppLogger
  static void _setupEnhancedConsole() {
    // 关键修复 1：注册全新的专属 Channel 'FluxConsoleLog'，杜绝因系统默认 'ConsoleLog' 已存在而被 setupBridge 拒绝注册忽略的底层缺陷
    _jsRuntime.onMessage('FluxConsoleLog', _handleConsoleLog);

    // 关键修复 2：强行接管默认注册的 'ConsoleLog' 管道，实现双通道兜底捕获
    try {
      JavascriptRuntime.channelFunctionsRegistered[_jsRuntime.getEngineInstanceId()]?['ConsoleLog'] = _handleConsoleLog;
    } catch (_) {}

    // 在 JS 全局注入强化版 console 代理
    _jsRuntime.evaluate('''
      (function() {
        function _fluxFormatArg(arg) {
          if (arg === null) return 'null';
          if (arg === undefined) return 'undefined';
          if (typeof arg === 'string') return arg;
          if (typeof arg === 'number' || typeof arg === 'boolean') return String(arg);
          if (arg instanceof Error) return (arg.stack || arg.message || String(arg));
          try {
            return JSON.stringify(arg);
          } catch (e) {
            return String(arg);
          }
        }

        function _fluxSendLog(level, args) {
          try {
            var parts = [];
            for (var i = 0; i < args.length; i++) {
              parts.push(_fluxFormatArg(args[i]));
            }
            var text = parts.join(' ');
            if (typeof sendMessage === 'function') {
              sendMessage('FluxConsoleLog', JSON.stringify([level, text]));
            }
          } catch (err) {}
        }

        var enhancedConsole = {
          log: function() { _fluxSendLog('INFO', arguments); },
          info: function() { _fluxSendLog('INFO', arguments); },
          warn: function() { _fluxSendLog('WARN', arguments); },
          error: function() { _fluxSendLog('ERROR', arguments); },
          debug: function() { _fluxSendLog('DEBUG', arguments); }
        };

        globalThis.console = enhancedConsole;
        if (typeof window !== 'undefined') window.console = enhancedConsole;
        if (typeof global !== 'undefined') global.console = enhancedConsole;
      })();
    ''');
  }

  /// 注入原生高性能 HTTP 适配器，配合 QuickJS-NG 与 Dio，彻底解决旧版内置 XHR 模板字符串反引号语法解析崩溃与轮询延时
  static void _setupNativeHttpBridge() {
    _jsRuntime.onMessage('FluxHttpRequest', _handleHttpRequest);

    _jsRuntime.evaluate('''
      (function() {
        globalThis._fluxHttpRequests = {};
        globalThis._fluxHttpReqId = 0;

        // 原生网络响应成功回调
        globalThis._fluxHttpResolve = function(res) {
          var entry = globalThis._fluxHttpRequests[res.reqId];
          if (!entry) return;
          delete globalThis._fluxHttpRequests[res.reqId];

          var validateStatus = (entry.config && entry.config.validateStatus) || function(status) {
            return status >= 200 && status < 300;
          };

          var response = {
            data: res.data,
            status: res.status,
            statusText: res.statusText || 'OK',
            headers: res.headers || {},
            config: entry.config,
            request: {}
          };

          if (validateStatus(res.status)) {
            entry.resolve(response);
          } else {
            var err = new Error('Request failed with status code ' + res.status);
            err.config = entry.config;
            err.response = response;
            err.isAxiosError = true;
            entry.reject(err);
          }
        };

        // 原生网络响应异常回调
        globalThis._fluxHttpReject = function(res) {
          var entry = globalThis._fluxHttpRequests[res.reqId];
          if (!entry) return;
          delete globalThis._fluxHttpRequests[res.reqId];

          var err = new Error(res.error || 'Network Error');
          err.config = entry.config;
          err.isAxiosError = true;
          entry.reject(err);
        };

        // 关键核心：接管 axios 的默认 adapter，走原生安全通道
        if (typeof axios !== 'undefined') {
          axios.defaults.adapter = function fluxNativeHttpAdapter(config) {
            return new Promise(function(resolve, reject) {
              var reqId = 'req_' + (++globalThis._fluxHttpReqId) + '_' + Date.now();
              globalThis._fluxHttpRequests[reqId] = {
                resolve: resolve,
                reject: reject,
                config: config
              };

              // 拼接完整 URL（支持相对路径与 baseURL 自动合并）
              var finalUrl = config.url || '';
              if (config.baseURL && !finalUrl.match(/^https?:\\/\\//i)) {
                var b = config.baseURL.replace(/\\/+\$/, '');
                var u = finalUrl.replace(/^\\/+/, '');
                finalUrl = b + '/' + u;
              }

              var payload = {
                reqId: reqId,
                method: (config.method || 'get').toUpperCase(),
                url: finalUrl,
                headers: config.headers || {},
                data: config.data,
                timeout: config.timeout,
                maxRedirects: config.maxRedirects,
                responseType: config.responseType || 'json'
              };

              if (typeof sendMessage === 'function') {
                sendMessage('FluxHttpRequest', JSON.stringify(payload));
              } else {
                reject(new Error('FluxHttpRequest native bridge not available'));
              }
            });
          };
        }
      })();
    ''');
  }

  /// 统一处理来自 JS 沙箱中 axios 发起的原生网络请求
  static void _handleHttpRequest(dynamic args) async {
    String? reqId;
    try {
      Map<String, dynamic> req;
      if (args is Map) {
        req = Map<String, dynamic>.from(args);
      } else if (args is String) {
        req = Map<String, dynamic>.from(jsonDecode(args) as Map);
      } else {
        return;
      }

      reqId = req['reqId']?.toString();
      if (reqId == null) return;

      final method = (req['method']?.toString() ?? 'GET').toUpperCase();
      final urlStr = req['url']?.toString().trim() ?? '';
      if (urlStr.isEmpty) {
        throw Exception('HTTP 请求 URL 不能为空');
      }

      final headers = <String, dynamic>{};
      if (req['headers'] is Map) {
        (req['headers'] as Map).forEach((k, v) {
          if (k != null && v != null) {
            headers[k.toString()] = v;
          }
        });
      }

      // 若未显式设置 User-Agent，自动注入防爬伪装 User-Agent
      if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
        headers['User-Agent'] = currentUserAgent;
      }

      // 确保 Cookie 拦截器就绪
      _attachCookieManager(cookieJar);

      final dynamic reqData = req['data'];
      final int timeoutMs = (req['timeout'] is num)
          ? (req['timeout'] as num).toInt()
          : (defaultTimeoutSeconds * 1000);

      // 读取重定向策略（默认最多跟随 5 次，若显式传 0 则禁用自动重定向，原样返回 3xx 状态码供规则自处理）
      final maxRedirects = (req['maxRedirects'] is num) ? (req['maxRedirects'] as num).toInt() : 5;

      Response<String> response;
      String currentUrl = urlStr;
      String currentMethod = method;
      dynamic currentData = reqData;
      int redirectCount = 0;

      while (true) {
        response = await _nativeDio.request<String>(
          currentUrl,
          data: currentData,
          options: Options(
            method: currentMethod,
            headers: headers,
            responseType: ResponseType.plain,
            validateStatus: (_) => true, // 允许所有状态码通过，交由 Axios 的 validateStatus 裁决
            sendTimeout: Duration(milliseconds: timeoutMs),
            receiveTimeout: Duration(milliseconds: timeoutMs),
          ),
        );

        final statusCode = response.statusCode ?? 200;
        final location = response.headers.value('location');

        // 针对 POST/GET 遇到 301/302/303/307/308 重定向，自动根据 HTTP 标准进行跟随
        // 彻底解决 Dart HttpClient 对 POST 302 默认不跟随导致的小说/站点搜索抛出 302 异常
        if (maxRedirects > 0 &&
            redirectCount < maxRedirects &&
            location != null &&
            location.trim().isNotEmpty &&
            (statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308)) {
          redirectCount++;
          try {
            currentUrl = Uri.parse(currentUrl).resolve(location.trim()).toString();
          } catch (_) {
            currentUrl = location.trim();
          }

          // RFC 7231 / 浏览器行为：301, 302, 303 遇到 POST 时标准行为转为 GET 并清空请求体
          if (statusCode == 301 || statusCode == 302 || statusCode == 303) {
            currentMethod = 'GET';
            currentData = null;
            headers.removeWhere((k, _) {
              final lk = k.toLowerCase();
              return lk == 'content-type' || lk == 'content-length';
            });
          }
          debugPrint('[RuleEngine/NativeHttp] 重定向 ($statusCode) -> $currentUrl (第 $redirectCount 次)');
          continue;
        }

        break;
      }

      final rawData = response.data ?? '';
      dynamic finalData = rawData;

      // 智能自适应处理：
      // 1. 若规则明确声明了 responseType 为 'text' 或 'stream'，保持原样纯字符串；
      // 2. 默认情况下，无论是 Content-Type 声明为 JSON，还是实际内容以 { 或 [ 开头，
      //    均自动反序列化为可直接点属性操作的 JS 对象（与 Axios 官方默认行为一致）；
      // 3. 若为 HTML 网页（<!DOCTYPE 或以 < 开头），安全保留为原始字符串，供 cheerio 解析。
      final reqResponseType = req['responseType']?.toString().toLowerCase() ?? 'json';
      if (reqResponseType != 'text' && reqResponseType != 'stream') {
        final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
        final trimmed = rawData.trim();
        final isJsonLikely = contentType.contains('application/json') ||
            contentType.contains('+json') ||
            ((trimmed.startsWith('{') && trimmed.endsWith('}')) || (trimmed.startsWith('[') && trimmed.endsWith(']')));

        if (isJsonLikely) {
          try {
            finalData = jsonDecode(rawData);
          } catch (_) {
            // 解析失败（如非标准 JSON）安全降级保留原字符串
            finalData = rawData;
          }
        }
      }

      final resHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        resHeaders[name] = values.join('; ');
      });

      // 关键安全机制：使用 jsonEncode 将包含反引号、\${}、换行符、反斜杠等任何字符的响应体完整编码为标准的 JSON 对象
      final resPayload = jsonEncode({
        'reqId': reqId,
        'status': response.statusCode ?? 200,
        'statusText': response.statusMessage ?? 'OK',
        'headers': resHeaders,
        'data': finalData,
      });

      _jsRuntime.evaluate('globalThis._fluxHttpResolve($resPayload);');
    } catch (e) {
      if (reqId != null) {
        final errPayload = jsonEncode({
          'reqId': reqId,
          'error': e.toString(),
        });
        try {
          _jsRuntime.evaluate('globalThis._fluxHttpReject($errPayload);');
        } catch (_) {}
      }
    }
  }

  /// 加载内置 JS 资源文件
  static Future<void> _loadJSFile(String path) async {
    try {
      String jsCode = await rootBundle.loadString(path);
      _jsRuntime.evaluate(jsCode);
    } catch (e) {
      debugPrint('Failed to load asset JS: $path, $e');
    }
  }

  /// 将标准 ESModule 语法自适应转译为适用于沙箱的 CommonJS 规范
  static String transformToRunnableJs(String code) {
    String clean = code.trim();

    // 1. 剔除顶层 import 语句 (沙箱已在全局预加载 axios / cheerio)
    final importRegex = RegExp(
      r'^\s*import\s+[\s\S]*?from\s+[\x22\x27][^\x22\x27]+[\x22\x27];?',
      multiLine: true,
    );
    clean = clean.replaceAll(importRegex, '').trim();

    // 2. 将 export default 规范化替换为 module.exports =
    if (clean.contains('export default')) {
      clean = clean.replaceAll(RegExp(r'export\s+default\s+'), 'module.exports = ');
    } else if (!clean.contains('module.exports') && !clean.contains('exports.')) {
      // 仅当整段代码是一个纯对象字面量（以 { 开头并以 } 结尾）时才包裹 module.exports = (...)
      // 严禁将含有 const / let / var / function 或以注释开头的代码前硬拼 module.exports =，避免破坏 JS 语法导致 SyntaxError
      final trimmed = clean.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        clean = 'module.exports = ($clean)';
      }
    }

    return clean;
  }

  /// 基础执行接口：传入 code 与上下文 context
  static Future<dynamic> execute(String code, [Map<String, dynamic>? context]) async {
    final ctx = context ?? {};
    final action = ctx['action']?.toString() ?? 'discovery';
    final params = ctx['params'] as Map<String, dynamic>? ?? {};
    final baseUrl = ctx['baseUrl']?.toString() ?? params['baseUrl']?.toString();
    final timeoutSeconds = ctx['timeoutSeconds'] as int?;
    final ruleName = ctx['ruleName']?.toString();

    return await executeRule(
      code: code,
      action: action,
      params: params,
      baseUrl: baseUrl,
      timeoutSeconds: timeoutSeconds,
      ruleName: ruleName,
    );
  }

  /// 标准生命周期沙箱调度调用（严格基于 defineRule 标准模板驱动）
  static Future<dynamic> executeRule({
    required String code,
    required String action,
    Map<String, dynamic>? params,
    String? baseUrl,
    int? timeoutSeconds,
    String? ruleName,
  }) async {
    if (!_initialized) {
      await init();
    }

    final effectiveRuleName = (ruleName != null && ruleName.trim().isNotEmpty)
        ? ruleName.trim()
        : 'Sandbox';
    
    // 设置当前正在执行的规则名称，让 JS console.log 能够打上正确的规则 Tag
    _currentRunningRuleName = effectiveRuleName;
    final stopwatch = Stopwatch()..start();

    final int timeoutSec = timeoutSeconds ?? defaultTimeoutSeconds;

    final effectiveParams = Map<String, dynamic>.from(params ?? {});
    final currentBaseUrl = baseUrl ?? effectiveParams['baseUrl']?.toString() ?? '';
    if (currentBaseUrl.isNotEmpty) {
      effectiveParams['baseUrl'] = currentBaseUrl;
    }

    AppLogger.addLog(
      level: 'DEBUG',
      tag: 'Rule: $effectiveRuleName',
      message: '沙箱启动动作 [$action] -> 参数: $effectiveParams',
    );

    final transformedJs = transformToRunnableJs(code);
    final encodedBaseUrl = jsonEncode(currentBaseUrl);
    final encodedParams = jsonEncode(effectiveParams);

    // 采用极简沙箱闭包容器（彻底移除重复声明的 50+ 行冗余脚手架代码，实现规则行号贴合）
    final script = '''
      (async () => {
        try {
          var module = { exports: {} };
          var exports = module.exports;
          var baseUrl = $encodedBaseUrl;

          if (typeof axios !== 'undefined' && axios.defaults) {
            axios.defaults.timeout = ${timeoutSec * 1000};
          }

          // 注入转译后的规则模块
          $transformedJs;

          var rule = module.exports || exports || globalThis._fluxLastDefinedRule;
          if (rule && rule.default) {
            rule = rule.default;
          }

          if (!rule || typeof rule !== 'object') {
            throw new Error('规则未导出有效对象，请使用 defineRule({ ... }) 或 export default');
          }

          var action = '$action';
          var fn = rule[action];

          if (typeof fn !== 'function') {
            throw new Error('规则对象中未定义生命周期方法 [' + action + ']');
          }

          var params = $encodedParams;
          // 严格按照标准模板契约执行生命周期方法：fn({ ...params })
          var result = await fn.call(rule, params);

          return JSON.stringify({
            success: true,
            data: (result === undefined) ? null : result
          });
        } catch (err) {
          var errMessage = '';
          if (err) {
            var msg = err.message || String(err);
            var details = [];
            if (err.isAxiosError) {
              if (err.response) {
                details.push('HTTP ' + err.response.status + (err.response.statusText ? ' ' + err.response.statusText : ''));
              }
              if (err.config && err.config.url) {
                details.push('URL: ' + err.config.url);
              }
            }
            if (details.length > 0) {
              msg += ' (' + details.join(', ') + ')';
            }
            // QuickJS-NG 的 stack 不包含 message，因此将 message 与 stack 完整拼接，避免被堆栈覆盖
            // 使用 String.fromCharCode(10) 生成换行，彻底杜绝 Dart 多行字符串将 \n 求值为物理换行导致的 JS SyntaxError
            if (err.stack) {
              msg += String.fromCharCode(10) + String(err.stack);
            }
            errMessage = msg;
          } else {
            errMessage = '未知执行错误';
          }
          try {
            console.error('[RuleEngine] 动作 [' + '$action' + '] 执行失败: ' + errMessage);
          } catch (_) {}
          return JSON.stringify({
            success: false,
            error: errMessage
          });
        }
      })()
    ''';

    try {
      JsEvalResult jsResult = _jsRuntime.evaluate(script);

      if (jsResult.isError) {
        final errText = jsResult.rawResult?.toString() ?? 'JavaScript 语法解析/执行错误';
        
        // 智能定位语法错误具体代码行与列号，输出精确代码切片
        final match = RegExp(r'<eval>:(\d+)(?::(\d+))?').firstMatch(errText);
        String diagnosticSnippet = '';
        if (match != null) {
          final lineNum = int.tryParse(match.group(1) ?? '') ?? 0;
          final colNum = int.tryParse(match.group(2) ?? '') ?? 0;
          if (lineNum > 0) {
            final scriptLines = script.split('\n');
            final start = (lineNum - 3).clamp(0, scriptLines.length);
            final end = (lineNum + 2).clamp(0, scriptLines.length);
            final buffer = StringBuffer('\n-------- 语法错误定位 (第 $lineNum 行第 $colNum 列) --------\n');
            for (int i = start; i < end; i++) {
              final isTarget = (i + 1 == lineNum);
              final prefix = isTarget ? '> ' : '  ';
              final lineStr = '${i + 1}'.padLeft(4);
              buffer.writeln('$prefix$lineStr | ${scriptLines[i]}');
              if (isTarget && colNum > 0) {
                buffer.writeln('       | ${' ' * (colNum - 1)}^');
              }
            }
            buffer.write('----------------------------------------------------');
            diagnosticSnippet = buffer.toString();
          }
        }

        debugPrint('-----------------沙箱语法/运行时错误-----------------$diagnosticSnippet');
        debugPrint(errText);
        AppLogger.addLog(
          level: 'ERROR',
          tag: 'Rule: $effectiveRuleName',
          message: '[$action] 语法/运行时错误: $errText$diagnosticSnippet',
        );
        throw Exception(errText);
      }

      var data = await _jsRuntime.handlePromise(
        jsResult,
        timeout: Duration(seconds: timeoutSec),
      );
      if (!data.isError) {
        stopwatch.stop();
        final raw = data.stringResult;
        if (raw.isEmpty || raw == 'undefined' || raw == 'null') {
          AppLogger.addLog(
            level: 'INFO',
            tag: 'Rule: $effectiveRuleName',
            message: '[$action] 执行完毕 (空响应) 耗时 ${stopwatch.elapsedMilliseconds}ms',
          );
          return null;
        }

        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          if (decoded['success'] == false) {
            final errText = decoded['error']?.toString() ?? '规则执行失败';
            AppLogger.addLog(
              level: 'ERROR',
              tag: 'Rule: $effectiveRuleName',
              message: '[$action] 业务执行异常: $errText',
            );
            throw Exception(errText);
          }
          final resultData = decoded['data'];
          final countInfo = resultData is List
              ? '返回 ${resultData.length} 项数据'
              : (resultData != null ? '返回对象数据' : '返回空数据');
          AppLogger.addLog(
            level: 'INFO',
            tag: 'Rule: $effectiveRuleName',
            message: '[$action] 执行成功 ($countInfo) 耗时 ${stopwatch.elapsedMilliseconds}ms',
          );
          return resultData;
        }

        return decoded;
      } else {
        final promiseErr = data.rawResult?.toString() ?? 'Promise rejected in sandbox';
        AppLogger.addLog(
          level: 'ERROR',
          tag: 'Rule: $effectiveRuleName',
          message: '[$action] 异步 Promise 异常: $promiseErr',
        );
        throw Exception(promiseErr);
      }
    } on TimeoutException {
      stopwatch.stop();
      final timeoutMsg = '规则执行超时 (超过 $timeoutSec 秒未响应，目标站点可能不可达或网络受阻)';
      debugPrint('【RuleEngine】规则沙箱执行超时 (${timeoutSec}s)');
      AppLogger.addLog(
        level: 'ERROR',
        tag: 'Rule: $effectiveRuleName',
        message: '[$action] 超时错误: $timeoutMsg (耗时 ${stopwatch.elapsedMilliseconds}ms)',
      );
      throw TimeoutException(timeoutMsg);
    } catch (e, stack) {
      stopwatch.stop();
      debugPrint('Rule execution error: $e');
      AppLogger.addLog(
        level: 'ERROR',
        tag: 'Rule: $effectiveRuleName',
        message: '[$action] 运行异常: $e (耗时 ${stopwatch.elapsedMilliseconds}ms)',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    } finally {
      // 执行完毕后恢复默认沙箱标识
      _currentRunningRuleName = 'Sandbox';
    }
  }

  /// 快捷生命周期动作：分类发现 (discovery)
  static Future<dynamic> discovery(
    Rule rule, {
    int page = 1,
    String? tab,
    int? timeoutSeconds,
  }) async {
    return await executeRule(
      code: rule.code,
      action: 'discovery',
      ruleName: rule.name,
      params: {
        'page': page,
        'tab': ?tab,
        'baseUrl': rule.baseUrl,
      },
      baseUrl: rule.baseUrl,
      timeoutSeconds: timeoutSeconds,
    );
  }

  /// 快捷生命周期动作：全局搜索 (search)
  static Future<dynamic> search(
    Rule rule,
    String keyword, {
    int page = 1,
    int? timeoutSeconds,
  }) async {
    return await executeRule(
      code: rule.code,
      action: 'search',
      ruleName: rule.name,
      params: {
        'keyword': keyword,
        'page': page,
        'baseUrl': rule.baseUrl,
      },
      baseUrl: rule.baseUrl,
      timeoutSeconds: timeoutSeconds,
    );
  }

  /// 快捷生命周期动作：详情元数据与选集 (detail)
  static Future<dynamic> detail(
    Rule rule,
    String url, {
    Map<String, dynamic>? item,
    int? timeoutSeconds,
  }) async {
    return await executeRule(
      code: rule.code,
      action: 'detail',
      ruleName: rule.name,
      params: {
        'url': url,
        'baseUrl': rule.baseUrl,
        'item': ?item,
      },
      baseUrl: rule.baseUrl,
      timeoutSeconds: timeoutSeconds,
    );
  }

  /// 快捷生命周期动作：播放直链嗅探与解析 (parse)
  static Future<dynamic> parse(
    Rule rule,
    String url, {
    String? groupName,
    int? timeoutSeconds,
  }) async {
    return await executeRule(
      code: rule.code,
      action: 'parse',
      ruleName: rule.name,
      params: {
        'url': url,
        'groupName': ?groupName,
        'baseUrl': rule.baseUrl,
      },
      baseUrl: rule.baseUrl,
      timeoutSeconds: timeoutSeconds,
    );
  }

  static void dispose() {
    _jsRuntime.dispose();
    _initialized = false;
    // 重置初始化任务缓存，确保 dispose 之后仍可重新初始化
    _initFuture = null;
  }
}
