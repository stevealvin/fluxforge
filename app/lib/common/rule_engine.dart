import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import '../model/rule.dart';

class RuleEngine {
  static final JavascriptRuntime _jsRuntime = getJavascriptRuntime();
  static bool _initialized = false;

  /// 初始化运行环境与注入核心依赖
  static Future<void> init() async {
    if (_initialized) return;
    try {
      _jsRuntime.evaluate('''
        var window = global = globalThis;
        var require = function(name) {
          if (name === 'axios') return axios;
          if (name === 'cheerio') return cheerio;
          return {};
        };
      ''');
      await _loadJSFile('assets/js/axios.min.js');
      await _loadJSFile('assets/js/cheerio.js');
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

  /// 将标准 ESModule 语法自适应转译为可执行的 JS 函数表达式
  static String transformToRunnableJs(String code) {
    String clean = code.trim();

    // 1. 剔除顶层 import 语句
    final importRegex = RegExp(r'^\s*import\s+[\s\S]*?from\s+[\x22\x27][^\x22\x27]+[\x22\x27];?', multiLine: true);
    clean = clean.replaceAll(importRegex, '').trim();

    // 2. 转换 export default 语法
    if (clean.contains('export default')) {
      clean = clean
          .replaceAll(
            RegExp(r'export\s+default\s+async\s+function\s*([a-zA-Z0-9_$]*)\s*\(([\s\S]*?)\)'),
            r'async function $1 ($2)',
          )
          .replaceAll(
            RegExp(r'export\s+default\s+function\s*([a-zA-Z0-9_$]*)\s*\(([\s\S]*?)\)'),
            r'function $1 ($2)',
          )
          .replaceAll(
            RegExp(r'export\s+default\s+async\s*\(?([\s\S]*?)\)?\s*=>'),
            r'async ($1) =>',
          )
          .replaceAll(
            RegExp(r'export\s+default\s*\(?([\s\S]*?)\)?\s*=>'),
            r'($1) =>',
          )
          .replaceAll(RegExp(r'export\s+default\s+'), '');
    }

    return clean;
  }

  /// 基础执行接口：传入 code 与上下文 context
  static Future<dynamic> execute(String code, [Map<String, dynamic>? context]) async {
    if (!_initialized) {
      await init();
    }

    final transformed = transformToRunnableJs(code);
    final ctxJson = jsonEncode(context ?? {});

    final script = '''
      (async () => {
        const ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
        if (typeof axios !== 'undefined' && axios.defaults && axios.defaults.headers) {
          axios.defaults.headers.common['User-Agent'] = ua;
        }

        const __ctx__ = $ctxJson;
        let __fn__;
        try {
          __fn__ = eval($transformed);
        } catch(e) {
          __fn__ = (function() {
            $transformed
            if (typeof main === 'function') return main;
            return null;
          })();
        }

        if (typeof __fn__ !== 'function') {
          throw new Error('Rule script must export or evaluate to a function');
        }

        const __result__ = await __fn__(__ctx__);
        return JSON.stringify(__result__);
      })()
    ''';

    JsEvalResult jsResult = _jsRuntime.evaluate(script);

    if (jsResult.isError) {
      debugPrint('-----------------沙箱语法错误-----------------');
      debugPrint('${jsResult.rawResult}');
      throw Exception(jsResult.rawResult?.toString() ?? 'JavaScript execution error');
    }

    try {
      var data = await _jsRuntime.handlePromise(jsResult);
      if (!data.isError) {
        return jsonDecode(data.stringResult);
      } else {
        throw Exception(data.rawResult?.toString() ?? 'Promise rejected in sandbox');
      }
    } catch (e) {
      debugPrint('Rule execution error: $e');
      rethrow;
    }
  }

  /// 标准生命周期调用：执行特定 action
  static Future<dynamic> executeRule({
    required String code,
    required String action,
    Map<String, dynamic>? params,
    String? baseUrl,
  }) async {
    final effectiveParams = Map<String, dynamic>.from(params ?? {});
    if (baseUrl != null && !effectiveParams.containsKey('baseUrl')) {
      effectiveParams['baseUrl'] = baseUrl;
    }

    final context = {
      'action': action,
      'params': effectiveParams,
    };

    return await execute(code, context);
  }

  /// 快捷生命周期动作：分类发现 (discovery)
  static Future<dynamic> discovery(Rule rule, {int page = 1, String? category}) async {
    return await executeRule(
      code: rule.code,
      action: 'discovery',
      params: {
        'page': page,
        'category': ?category,
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
