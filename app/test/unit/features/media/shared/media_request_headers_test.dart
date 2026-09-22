import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/media/shared/media_request_headers.dart';

/// 媒体资源请求头兜底
///
/// 锁定「发现页能出图、详情页 403」的根因契约：直连资源必须带上 UA，
/// 且规则显式声明的头一律不被覆盖。
void main() {
  group('MediaRequestHeaders.withDefaults', () {
    test('补齐缺失的 Referer 与 UA', () {
      final headers = MediaRequestHeaders.withDefaults(
        const {},
        referer: 'https://example.com/detail/1',
        userAgent: 'TestUA/1.0',
      );

      expect(headers['Referer'], 'https://example.com/detail/1');
      expect(headers['User-Agent'], 'TestUA/1.0');
    });

    test('不覆盖规则已声明的 Referer / UA（大小写不敏感）', () {
      final headers = MediaRequestHeaders.withDefaults(
        const {'referer': 'https://rule.example', 'user-agent': 'RuleUA'},
        referer: 'https://detail.example/detail/1',
        userAgent: 'DefaultUA',
      );

      expect(headers['referer'], 'https://rule.example');
      expect(headers['user-agent'], 'RuleUA');
      expect(headers.containsKey('Referer'), isFalse);
      expect(headers.containsKey('User-Agent'), isFalse);
      expect(headers.length, 2);
    });

    test('不改动入参（纯函数）', () {
      final input = <String, String>{'Cookie': 'a=1'};
      final result = MediaRequestHeaders.withDefaults(
        input,
        referer: 'https://example.com',
        userAgent: 'UA',
      );

      expect(input.length, 1, reason: '入参不被就地修改');
      expect(result.length, 3);
    });

    test('referer 为空时只补 UA', () {
      final headers = MediaRequestHeaders.withDefaults(
        const {},
        userAgent: 'UA',
      );

      expect(headers.containsKey('Referer'), isFalse);
      expect(headers['User-Agent'], 'UA');
    });

    test('userAgent 为空白时不写入空头', () {
      final headers = MediaRequestHeaders.withDefaults(
        const {},
        userAgent: '   ',
      );

      expect(headers.containsKey('User-Agent'), isFalse);
    });

    test('默认 UA 在依赖未就绪时也能取到非空值', () {
      // 单测环境未初始化 DI：应回退内置默认 UA，而不是抛错或返回空串
      expect(MediaRequestHeaders.defaultUserAgent.trim(), isNotEmpty);
    });
  });

  group('MediaRequestHeaders.resolveReferer', () {
    test('规则 baseUrl 优先（站点根，与发现页同口径）', () {
      expect(
        MediaRequestHeaders.resolveReferer(
          ruleBaseUrl: 'https://meirentu.cc',
          pageUrl: 'https://meirentu.cc/art/12345.html',
        ),
        'https://meirentu.cc',
      );
    });

    test('baseUrl 带空白时修剪后使用', () {
      expect(
        MediaRequestHeaders.resolveReferer(
          ruleBaseUrl: '  https://meirentu.cc  ',
        ),
        'https://meirentu.cc',
      );
    });

    test('无 baseUrl 时退到页面地址的站点根，而不是深层地址', () {
      // 深层页面地址（甚至接口地址）会被图床判为盗链，站点根才安全
      expect(
        MediaRequestHeaders.resolveReferer(
          pageUrl: 'https://meirentu.cc/art/12345.html?from=list',
        ),
        'https://meirentu.cc',
      );
    });

    test('都为空时返回空串（交由调用方决定是否写入）', () {
      expect(MediaRequestHeaders.resolveReferer(), '');
      expect(MediaRequestHeaders.resolveReferer(ruleBaseUrl: '  '), '');
      expect(MediaRequestHeaders.resolveReferer(pageUrl: '  '), '');
    });

    test('页面地址不是绝对 URL 时原样返回', () {
      expect(
        MediaRequestHeaders.resolveReferer(pageUrl: '/art/12345.html'),
        '/art/12345.html',
      );
    });
  });
}
