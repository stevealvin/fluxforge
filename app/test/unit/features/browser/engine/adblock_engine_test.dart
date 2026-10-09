import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/features/browser/engine/adblock_engine.dart';

/// 广告拦截引擎测试
///
/// 覆盖四块：种子规则与基础判定、注入脚本组装、ABP 规则解析分类、拦截计数。
///
/// 引擎是共享单例、规则索引只增不减，因此「解析分类」组的用例一律使用
/// **互不重叠的域名**（断言里那些 -test-x 后缀就是为此），避免用例互相污染。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final engine = AdBlockEngine.instance;

  group('种子规则与基础判定', () {
    test('Seed blacklist blocks common ad networks', () {
      expect(engine.shouldBlock('https://pos.baidu.com/auto.js'), isTrue);
      expect(engine.shouldBlock('https://cpro.baidustatic.com/cpro/ui/c.js'), isTrue);
      expect(engine.shouldBlock('https://s9.cnzz.com/z_stat.php'), isTrue);
      expect(engine.shouldBlock('https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'), isTrue);
      expect(engine.shouldBlock('https://tanx.com/ad/show'), isTrue);
      expect(engine.shouldBlock('https://mi.gdt.qq.com/gdt_m.js'), isTrue);
    });

    test('Benign URLs are not blocked', () {
      expect(engine.shouldBlock('https://www.bilibili.com/video/BV123'), isFalse);
      expect(engine.shouldBlock('https://m.iqiyi.com/v_123.html'), isFalse);
      expect(engine.shouldBlock('https://v.qq.com/x/cover/123.html'), isFalse);
      expect(engine.shouldBlock('data:image/png;base64,iVBORw0KGgo='), isFalse);
      expect(engine.shouldBlock('about:blank'), isFalse);
    });

    test('Subdomain matching matches parent domain in blacklist', () {
      expect(engine.shouldBlock('https://sub3.pos.baidu.com/ad.js'), isTrue);
      expect(engine.shouldBlock('https://ad.tanx.com/code'), isTrue);
    });
  });

  group('规则解析分类', () {
    test('||domain^ 进域名黑名单，且支持父域回溯', () {
      engine.parseRuleContent('||ads-test-a.com^');

      expect(engine.shouldBlock('https://ads-test-a.com/banner.js'), isTrue);
      expect(
        engine.shouldBlock('https://sub.ads-test-a.com/x.png'),
        isTrue,
        reason: '子域应沿父域逐级回溯命中',
      );
      expect(engine.shouldBlock('https://unrelated-zz.com/x.png'), isFalse);
    });

    test('带路径的规则支持 ABP 通配符 *', () {
      engine.parseRuleContent('''
||static-test-b.com/ads/*
||static-test-c.com/js/promo.js
''');

      expect(
        engine.shouldBlock('https://static-test-b.com/ads/banner.png'),
        isTrue,
        reason: '此前一律用 contains，含 * 的规则永远匹配不上（URL 里没有 * 字面量）',
      );
      expect(
        engine.shouldBlock('https://static-test-b.com/normal/a.png'),
        isFalse,
      );
      expect(
        engine.shouldBlock('https://static-test-c.com/js/promo.js?v=2'),
        isTrue,
      );
    });

    test('白名单优先于黑名单', () {
      engine.parseRuleContent('''
||conflict-test-d.com^
@@||conflict-test-d.com^
''');

      expect(engine.shouldBlock('https://conflict-test-d.com/a.js'), isFalse);
    });

    test(r'$修饰符被截断，域名部分仍然生效', () {
      engine.parseRuleContent('||track-test-e.net^\$third-party');

      expect(engine.shouldBlock('https://track-test-e.net/p.gif'), isTrue);
    });

    test('#@# 例外选择器会被从隐藏列表中剔除', () {
      engine.parseRuleContent('''
example-test-f.com##.ad-banner-zz
example-test-f.com#@#.ad-banner-zz
''');

      final selectors = engine.getCosmeticSelectorsForUrl(
        'https://example-test-f.com/page',
      );
      expect(
        selectors,
        isNot(contains('.ad-banner-zz')),
        reason: '订阅源明确要求放行的选择器不得再被隐藏',
      );
    });

    test('通用隐藏规则与域名限定规则各自归类', () {
      engine.parseRuleContent('''
##.generic-ad-zz
example-test-g.com##.site-ad-zz
''');

      final matched = engine.getCosmeticSelectorsForUrl(
        'https://example-test-g.com/',
      );
      expect(matched, contains('.generic-ad-zz'));
      expect(matched, contains('.site-ad-zz'));

      final other = engine.getCosmeticSelectorsForUrl(
        'https://other-site-zz.com/',
      );
      expect(other, contains('.generic-ad-zz'));
      expect(
        other,
        isNot(contains('.site-ad-zz')),
        reason: '域名限定规则不该泄漏到其它站点',
      );
    });

    test('注释行与文件头被忽略，且返回值只计有效规则', () {
      final count = engine.parseRuleContent('''
! 这是注释
[Adblock Plus 2.0]
||ignored-test-h.com^
''');

      expect(count, 1);
      expect(engine.shouldBlock('https://ignored-test-h.com/a.js'), isTrue);
    });
  });

  group('注入脚本', () {
    test('Generates valid and safe Content Script for WebView', () {
      final script = engine.buildContentScriptForUrl('https://m.bilibili.com/video/123');

      expect(script, contains('window.__fluxforge_adblock_installed'));
      // 规则数据改为挂在 window 上的对象（支持重复注入时整体刷新），
      // 因此这里的断言随之更新：域名/选择器不再是一组裸常量
      expect(script, contains('window.__ff_adblock_rules'));
      expect(script, contains('domains: new Set('));
      expect(script, contains('selectors: _splitLines('));
      expect(script, contains('applyCosmeticFilters()'));
      expect(script, contains('MutationObserver'));
      expect(script, contains('origOpen = window.open'));
      expect(script, contains('origFetch = window.fetch'));
      expect(script, contains('origOpen = XMLHttpRequest.prototype.open'));
      expect(script, contains('HTMLScriptElement.prototype'));
      expect(script, contains('HTMLIFrameElement.prototype'));
    });

    test('携带可刷新的全局规则对象与拦截计数通道', () {
      final script = engine.buildContentScriptForUrl('https://example.com/');

      expect(script, contains('FluxAdBlockChannel'));
      // 紧凑换行编码 + 重复注入时的数据刷新路径
      expect(script, contains("split('\\n')"));
    });

    test('含通配符的规则被转成正则源码注入', () {
      engine.parseRuleContent('||wild-test-i.com/ads/*');

      final script = engine.buildContentScriptForUrl('https://example.com/');

      // 域名里的 `.` 会被转义成正则的 `\.`（这是刻意的：避免 `.` 通配任意字符）
      expect(script, contains(r'wild-test-i\.com/ads/.*'));
    });
  });

  group('拦截计数', () {
    test('按增量累加', () {
      final before = engine.blockedCountNotifier.value;

      engine.reportBlockedFromPage(3);
      engine.reportBlockedFromPage(2);

      expect(engine.blockedCountNotifier.value, before + 5);
    });

    test('非正增量被忽略', () {
      final before = engine.blockedCountNotifier.value;

      engine.reportBlockedFromPage(0);
      engine.reportBlockedFromPage(-5);

      expect(engine.blockedCountNotifier.value, before);
    });
  });
}
