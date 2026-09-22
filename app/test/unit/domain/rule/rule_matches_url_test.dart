import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/rule/rule.dart';

/// 规则与地址的匹配：**以 baseUrl 为唯一判据**
///
/// 回归重点：旧的 `url.contains(Uri.parse(baseUrl).host)` 写法有两个坑 ——
/// baseUrl 缺 scheme 时 host 是空串（任何字符串都包含空串 → 恒真），
/// 以及 `notexample.com` 会被 `example.com` 命中。
void main() {
  Rule rule(String baseUrl, {bool enabled = true}) => Rule(
    id: 1,
    name: '测试源',
    baseUrl: baseUrl,
    type: 'comic',
    code: '// noop',
    enabled: enabled,
  );

  test('前缀匹配：地址属于该站点', () {
    expect(
      rule('https://www.site.com').matchesUrl('https://www.site.com/detail/1'),
      isTrue,
    );
    expect(
      rule('https://www.site.com/manga/')
          .matchesUrl('https://www.site.com/manga/1163.html'),
      isTrue,
    );
  });

  test('同域容错：协议与 www 差异不该导致匹配失败', () {
    expect(rule('https://site.com').matchesUrl('http://site.com/d/1'), isTrue);
    expect(
      rule('https://www.site.com').matchesUrl('https://site.com/d/1'),
      isTrue,
    );
    expect(
      rule('https://SITE.com').matchesUrl('https://www.site.com/d/1'),
      isTrue,
    );
  });

  test('不相关站点不命中', () {
    expect(
      rule('https://site.com').matchesUrl('https://other.com/d/1'),
      isFalse,
    );
  });

  test('不被包含关系骗到（notexample.com 不该命中 example.com）', () {
    expect(
      rule('https://example.com').matchesUrl('https://notexample.com/d/1'),
      isFalse,
    );
  });

  test('缺 scheme 的 baseUrl 不再恒真', () {
    expect(rule('example.com').matchesUrl('https://other.com/d/1'), isFalse);
  });

  test('空地址 / 空 baseUrl 不命中', () {
    expect(rule('https://site.com').matchesUrl(''), isFalse);
    expect(rule('').matchesUrl('https://site.com/d/1'), isFalse);
  });
}
