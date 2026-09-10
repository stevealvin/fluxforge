import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/views/browser/adblock_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdBlockEngine Tests', () {
    final engine = AdBlockEngine.instance;

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

    test('Generates valid and safe Content Script for WebView', () {
      final script = engine.buildContentScriptForUrl('https://m.bilibili.com/video/123');
      expect(script, contains('window.__fluxforge_adblock_installed'));
      expect(script, contains('BLOCKED_DOMAINS = new Set('));
      expect(script, contains('COSMETIC_SELECTORS = ['));
      expect(script, contains('applyCosmeticFilters()'));
      expect(script, contains('MutationObserver'));
      expect(script, contains('origOpen = window.open'));
      expect(script, contains('origFetch = window.fetch'));
      expect(script, contains('origOpen = XMLHttpRequest.prototype.open'));
      expect(script, contains('HTMLScriptElement.prototype'));
      expect(script, contains('HTMLIFrameElement.prototype'));
    });
  });
}
