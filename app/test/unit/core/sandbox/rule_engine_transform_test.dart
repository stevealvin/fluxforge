import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/core/sandbox/rule_engine.dart';

void main() {
  testWidgets('RuleEngine standard template transformToRunnableJs cleanly converts export default to module.exports', (WidgetTester tester) async {
    const standardTemplateCode = '''
import axios from 'axios';
import cheerio from 'cheerio';

export default defineRule({
  async discovery({ tab = '', page = 1 }) {
    let url = `\${baseUrl}/page/\${page}`;
    console.log('发现列表', url);
    return { items: [] };
  },
  async search({ keyword, page = 1 }) {
    return { items: [] };
  },
  async detail({ url, item }) {
    console.log('detail详情', url);
    return { title: '测试详情' };
  },
  async parse({ url, groupName }) {
    return { playUrl: url };
  }
})
''';

    final runnableJs = RuleEngine.transformToRunnableJs(standardTemplateCode);
    // 1. 验证移除了顶层 import 语句
    expect(runnableJs.contains("import axios from 'axios'"), isFalse);
    expect(runnableJs.contains("import cheerio from 'cheerio'"), isFalse);

    // 2. 验证 export default defineRule 规范转换为 module.exports = defineRule
    expect(runnableJs.startsWith('module.exports = defineRule({'), isTrue);
    expect(runnableJs.contains("async detail({ url, item })"), isTrue);
  });

  test('RuleEngine handles standalone defineRule with top-level comments and constants cleanly without syntax corruption', () {
    const rawJs = '''
// 这是一个包含顶部注释和常量的规则
const API_BASE = 'https://example.com';
const TIMEOUT = 5000;

defineRule({
  async discovery({ page = 1 }) {
    return { items: [] };
  }
});
''';
    final runnableJs = RuleEngine.transformToRunnableJs(rawJs);
    // 验证绝不生成非法的 module.exports = const ... 或 module.exports = // ...
    expect(runnableJs.contains('module.exports = const'), isFalse);
    expect(runnableJs.contains('module.exports = //'), isFalse);
    expect(runnableJs.contains('const API_BASE'), isTrue);
    expect(runnableJs.contains('defineRule({'), isTrue);
  });

  test('RuleEngine transformToRunnableJs cleanly handles import crypto / CryptoJS and preserves crypto execution statements', () {
    const cryptoRuleCode = '''
import axios from 'axios';
import cheerio from 'cheerio';
import crypto from 'crypto';
import CryptoJS from 'crypto-js';

export default defineRule({
  async discovery() {
    const md5Hex = crypto.createHash('md5').update('hello').digest('hex');
    const hmacHex = crypto.createHmac('sha256', 'secret_key').update('hello').digest('hex');
    const cjsMd5 = CryptoJS.MD5('hello').toString();
    return {
      md5: md5Hex,
      hmac: hmacHex,
      cjsMd5: cjsMd5
    };
  }
});
''';

    final runnableJs = RuleEngine.transformToRunnableJs(cryptoRuleCode);
    // 验证 import 语句均被干净剔除，不留语法残渣
    expect(runnableJs.contains("import crypto from 'crypto'"), isFalse);
    expect(runnableJs.contains("import CryptoJS from 'crypto-js'"), isFalse);
    // 验证核心加密调用与生命周期方法被完整保留
    expect(runnableJs.contains("crypto.createHash('md5')"), isTrue);
    expect(runnableJs.contains("crypto.createHmac('sha256'"), isTrue);
    expect(runnableJs.contains("CryptoJS.MD5('hello')"), isTrue);
    expect(runnableJs.startsWith('module.exports = defineRule({'), isTrue);
  });
}
