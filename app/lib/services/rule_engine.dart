import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import '../core/utils/app_logger.dart';
import '../models/rule.dart';
import 'app_service.dart';
import 'di.dart';

/// FluxForge 本地高性能 JavaScript 沙箱执行引擎
/// 负责注入 axios、cheerio 与 Node.js 兼容环境，调度执行规则的 discovery、search、detail、parse 生命周期
/// 内置 console.log 拦截器，打通 JS 沙箱与 Dart 端的 AppLogger 全链路日志诊断
class RuleEngine {
  static final JavascriptRuntime _jsRuntime = getJavascriptRuntime();
  static bool _initialized = false;

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

      // 1. 基础全局环境注入
      _jsRuntime.evaluate('''
        var window = global = globalThis;
        var ua = $encodedUa;
        // 关键沙箱环境支持：注入 defineRule 规则声明包裹器
        var defineRule = function(r) { return r; };
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

      _initialized = true;
      AppLogger.addLog(
        level: 'INFO',
        tag: 'Rule Sandbox',
        message: 'QuickJS 沙箱内核初始化就绪 (Node.js 兼容层/Axios/Cheerio 已加载)',
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

  /// 注入强化版 console 代理，捕获规则内的 log/info/warn/error/debug 并转发到 AppLogger
  static void _setupEnhancedConsole() {
    // 在 JS 全局注入 console 代理，支持多参数安全展开与序列化
    _jsRuntime.evaluate('''
      (function() {
        function formatArg(arg) {
          if (arg === null) return 'null';
          if (arg === undefined) return 'undefined';
          if (typeof arg === 'object') {
            try {
              return JSON.stringify(arg);
            } catch (e) {
              return String(arg);
            }
          }
          return String(arg);
        }

        function sendToDart(level, args) {
          try {
            var parts = [];
            for (var i = 0; i < args.length; i++) {
              parts.push(formatArg(args[i]));
            }
            var text = parts.join(' ');
            sendMessage('ConsoleLog', JSON.stringify([level, text]));
          } catch (err) {}
        }

        globalThis.console = {
          log: function() { sendToDart('INFO', arguments); },
          info: function() { sendToDart('INFO', arguments); },
          warn: function() { sendToDart('WARN', arguments); },
          error: function() { sendToDart('ERROR', arguments); },
          debug: function() { sendToDart('DEBUG', arguments); }
        };
      })();
    ''');

    // 注册桥接处理函数，接收 JS 端回传的日志并打入 AppLogger
    _jsRuntime.onMessage('ConsoleLog', (dynamic args) {
      try {
        if (args is List && args.isNotEmpty) {
          final level = args[0]?.toString().toUpperCase() ?? 'INFO';
          final message = args.length > 1 ? args[1]?.toString() ?? '' : '';
          final tag = _currentRunningRuleName.isNotEmpty
              ? 'Rule: $_currentRunningRuleName'
              : 'Rule Sandbox';

          AppLogger.addLog(
            level: level,
            tag: tag,
            message: message,
          );
        }
      } catch (e) {
        debugPrint('[RuleEngine] ConsoleLog dispatch error: $e');
      }
    });
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

    // 2. 将 export default 规范化替换为 module.exports
    if (clean.contains('export default')) {
      clean = clean
          .replaceAll(
            RegExp(r'export\s+default\s+async\s+function\s*([\w]+)?\s*\(\s*([\w\s,]*)\s*\)'),
            r'module.exports = async function $1 ($2)',
          )
          .replaceAll(
            RegExp(r'export\s+default\s+function\s*([\w]+)?\s*\(\s*([\w\s,]*)\s*\)'),
            r'module.exports = function $1 ($2)',
          )
          .replaceAll(
            RegExp(r'export\s+default\s+async\s*\(?\s*([\w\s,]*)\s*\)?\s*=>'),
            r'module.exports = async ($1) =>',
          )
          .replaceAll(
            RegExp(r'export\s+default\s*\(?\s*([\w\s,]*)\s*\)?\s*=>'),
            r'module.exports = ($1) =>',
          )
          .replaceAll(RegExp(r'export\s+default\s+'), 'module.exports = ');
    } else if (!clean.contains('module.exports') && !clean.contains('exports.')) {
      clean = 'module.exports = $clean';
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

  /// 标准生命周期沙箱调度调用
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
    final String currentUa = currentUserAgent;
    final encodedUa = jsonEncode(currentUa);

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

    // 采用沙箱闭包容器，避免嵌套 eval 引起的语法错误断裂
    final script = '''
      (async () => {
        var module = { exports: {} };
        var exports = module.exports;
        var baseUrl = $encodedBaseUrl;
        var ua = $encodedUa;

        if (typeof axios !== 'undefined' && axios.defaults) {
          if (axios.defaults.headers) {
            axios.defaults.headers.common['User-Agent'] = ua;
          }
          axios.defaults.timeout = ${timeoutSec * 1000};
        }

        // 注入转译后的规则模块
        $transformedJs;

        var __exported__ = module.exports || exports;
        var __params__ = $encodedParams;
        var __action__ = '$action';

        var __result__;
        if (typeof __exported__ === 'function') {
          var __ctx__ = { action: __action__, params: __params__ };
          __result__ = await __exported__(__ctx__);
        } else if (__exported__ && typeof __exported__ === 'object') {
          var __fn__ = typeof __exported__[__action__] === 'function'
            ? __exported__[__action__]
            : (__exported__.default && typeof __exported__.default[__action__] === 'function'
                ? __exported__.default[__action__]
                : null);

          if (typeof __fn__ === 'function') {
            __result__ = await __fn__.call(__exported__, __params__);
          } else {
            throw new Error('Rule does not export method for action: ' + __action__);
          }
        } else {
          __result__ = __exported__;
        }

        return JSON.stringify(__result__);
      })()
    ''';

    try {
      JsEvalResult jsResult = _jsRuntime.evaluate(script);

      if (jsResult.isError) {
        final errText = jsResult.rawResult?.toString() ?? 'JavaScript 语法解析/执行错误';
        debugPrint('-----------------沙箱语法/运行时错误-----------------');
        debugPrint(errText);
        AppLogger.addLog(
          level: 'ERROR',
          tag: 'Rule: $effectiveRuleName',
          message: '[$action] 语法/运行时错误: $errText',
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
        final countInfo = decoded is List ? '返回 ${decoded.length} 项数据' : '返回对象数据';
        AppLogger.addLog(
          level: 'INFO',
          tag: 'Rule: $effectiveRuleName',
          message: '[$action] 执行成功 ($countInfo) 耗时 ${stopwatch.elapsedMilliseconds}ms',
        );
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
