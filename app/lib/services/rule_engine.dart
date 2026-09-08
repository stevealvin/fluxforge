import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import '../models/rule.dart';

/// FluxForge 本地高性能 JavaScript 沙箱执行引擎
/// 负责注入 axios、cheerio 与 Node.js 兼容环境，调度执行规则的 discovery、search、detail、parse 生命周期
class RuleEngine {
  static final JavascriptRuntime _jsRuntime = getJavascriptRuntime();
  static bool _initialized = false;

  /// 初始化运行环境与注入核心依赖
  static Future<void> init() async {
    if (_initialized) return;
    try {
      _jsRuntime.evaluate('''
        var window = global = globalThis;
        var ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
        // 关键沙箱环境支持：注入 defineRule 规则声明包裹器
        var defineRule = function(r) { return r; };
        var require = function(name) {
          if (name === 'axios') return axios;
          if (name === 'cheerio') return cheerio;
          return {};
        };
      ''');

      // 加载内置 JS 运行库 (标准 Web API polyfill, axios 与 cheerio)
      await _loadJSFile('assets/js/url.polyfill.js');
      await _loadJSFile('assets/js/axios.min.js');
      await _loadJSFile('assets/js/cheerio.js');

      _jsRuntime.evaluate('''
        if (typeof axios !== 'undefined' && axios.defaults && axios.defaults.headers) {
          axios.defaults.headers.common['User-Agent'] = ua;
        }
      ''');

      _initialized = true;
    } catch (e) {
      debugPrint('RuleEngine init error: $e');
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

    return await executeRule(
      code: code,
      action: action,
      params: params,
      baseUrl: baseUrl,
    );
  }

  /// 标准生命周期沙箱调度调用
  static Future<dynamic> executeRule({
    required String code,
    required String action,
    Map<String, dynamic>? params,
    String? baseUrl,
  }) async {
    if (!_initialized) {
      await init();
    }

    final effectiveParams = Map<String, dynamic>.from(params ?? {});
    final currentBaseUrl = baseUrl ?? effectiveParams['baseUrl']?.toString() ?? '';
    if (currentBaseUrl.isNotEmpty) {
      effectiveParams['baseUrl'] = currentBaseUrl;
    }

    final transformedJs = transformToRunnableJs(code);
    final encodedBaseUrl = jsonEncode(currentBaseUrl);
    final encodedParams = jsonEncode(effectiveParams);

    // 采用沙箱闭包容器，避免嵌套 eval 引起的语法错误断裂
    final script = '''
      (async () => {
        var module = { exports: {} };
        var exports = module.exports;
        var baseUrl = $encodedBaseUrl;
        var ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';

        // 注入转译后的规则模块
        $transformedJs;

        var __exported__ = module.exports || exports;
        var __params__ = $encodedParams;
        var __action__ = '$action';

        var __result__;
        if (typeof __exported__ === 'function') {
          // 兼容契约单函数模式: export default async function(context)
          var __ctx__ = { action: __action__, params: __params__ };
          __result__ = await __exported__(__ctx__);
        } else if (__exported__ && typeof __exported__ === 'object') {
          // 兼容契约对象模式: export default defineRule({ discovery, search, detail, parse })
          var __actionMap__ = {
            'discovery': ['discovery', 'explore', 'latest', 'list'],
            'detail': ['detail', 'getDetail', 'info'],
            'search': ['search', 'searchList'],
            'parse': ['parse', 'watch', 'content']
          };
          var __candidates__ = __actionMap__[__action__] || [__action__];
          var __fn__ = null;
          for (var i = 0; i < __candidates__.length; i++) {
            var name = __candidates__[i];
            if (typeof __exported__[name] === 'function') {
              __fn__ = __exported__[name];
              break;
            }
          }
          if (!__fn__ && typeof __exported__.default === 'function') {
            __fn__ = __exported__.default;
          }
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

    JsEvalResult jsResult = _jsRuntime.evaluate(script);

    if (jsResult.isError) {
      debugPrint('-----------------沙箱语法/运行时错误-----------------');
      debugPrint('${jsResult.rawResult}');
      throw Exception(jsResult.rawResult?.toString() ?? 'JavaScript execution error');
    }

    try {
      var data = await _jsRuntime.handlePromise(
        jsResult,
        timeout: const Duration(seconds: 60),
      );
      if (!data.isError) {
        final raw = data.stringResult;
        if (raw.isEmpty || raw == 'undefined' || raw == 'null') {
          return null;
        }
        return jsonDecode(raw);
      } else {
        throw Exception(data.rawResult?.toString() ?? 'Promise rejected in sandbox');
      }
    } on TimeoutException {
      debugPrint('【RuleEngine】规则沙箱执行超时 (60s)');
      throw TimeoutException('规则执行超时 (超过 60 秒未响应，目标站点可能不可达或网络受阻)');
    } catch (e) {
      debugPrint('Rule execution error: $e');
      rethrow;
    }
  }

  /// 快捷生命周期动作：分类发现 (discovery)
  static Future<dynamic> discovery(
    Rule rule, {
    int page = 1,
    String? category,
    String? tab,
  }) async {
    final effectiveTab = tab ?? category;
    return await executeRule(
      code: rule.code,
      action: 'discovery',
      params: {
        'page': page,
        'tab': ?effectiveTab,
        'category': ?effectiveTab,
        'baseUrl': rule.baseUrl,
      },
      baseUrl: rule.baseUrl,
    );
  }

  /// 快捷生命周期动作：全局搜索 (search)
  static Future<dynamic> search(Rule rule, String keyword, {int page = 1}) async {
    return await executeRule(
      code: rule.code,
      action: 'search',
      params: {
        'keyword': keyword,
        'page': page,
        'baseUrl': rule.baseUrl,
      },
      baseUrl: rule.baseUrl,
    );
  }

  /// 快捷生命周期动作：详情元数据与选集 (detail)
  static Future<dynamic> detail(Rule rule, String url) async {
    return await executeRule(
      code: rule.code,
      action: 'detail',
      params: {
        'url': url,
        'baseUrl': rule.baseUrl,
      },
      baseUrl: rule.baseUrl,
    );
  }

  /// 快捷生命周期动作：播放直链嗅探与解析 (parse)
  static Future<dynamic> parse(Rule rule, String url, {String? episodeId}) async {
    return await executeRule(
      code: rule.code,
      action: 'parse',
      params: {
        'url': url,
        'episodeId': ?episodeId,
        'baseUrl': rule.baseUrl,
      },
      baseUrl: rule.baseUrl,
    );
  }

  static void dispose() {
    _jsRuntime.dispose();
    _initialized = false;
  }
}

