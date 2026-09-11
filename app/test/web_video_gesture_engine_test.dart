import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/views/browser/web_video_gesture_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebVideoGestureEngine Script Generation Tests', () {
    final engine = WebVideoGestureEngine.instance;

    test('Generates complete video gesture script with global capture and HUD', () {
      final script = engine.buildVideoGestureScript();

      // 1. 验证全局捕获级监听器
      expect(script, contains('window.addEventListener(\'touchstart\', onGlobalTouchStart, { capture: true, passive: false });'));
      expect(script, contains('window.addEventListener(\'touchmove\', onGlobalTouchMove, { capture: true, passive: false });'));
      expect(script, contains('window.addEventListener(\'touchend\', onGlobalTouchEnd, { capture: true, passive: false });'));

      // 2. 验证防全屏失焦与防死循环保护
      expect(script, contains('Object.defineProperty(document, \'hidden\''));
      expect(script, contains('Object.defineProperty(document, \'visibilityState\''));
      expect(script, contains('window.addEventListener(\'visibilitychange\''));
      expect(script, contains('HTMLMediaElement.prototype.pause'));
      expect(script, contains('HTMLMediaElement.prototype.play'));

      // 3. 验证智能触控命中探测
      expect(script, contains('findActiveVideoAndRectAtPoint'));

      // 4. 验证 HUD 与三轴手势（横向快退进、纵向亮度和音量、长按倍速）
      expect(script, contains('__ff_video_hud'));
      expect(script, contains('showSeekHud'));
      expect(script, contains('showBrightnessHud'));
      expect(script, contains('showVolumeHud'));
      expect(script, contains('showStatusHud'));
      expect(script, contains('3.0X 瞬时倍速中'));

      // 验证自定义倍率注入
      final customScript = engine.buildVideoGestureScript(longPressSpeed: 2.0);
      expect(customScript, contains('2.0X 瞬时倍速中'));

      // 5. 验证全屏动态挂载适配
      expect(script, contains('document.fullscreenElement || document.webkitFullscreenElement'));
    });
  });
}
