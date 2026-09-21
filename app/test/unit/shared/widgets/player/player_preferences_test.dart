import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/shared/widgets/player/player_preferences.dart';

/// 播放器偏好值对象测试
///
/// 它是 `AuraPlayer` 与设置仓储解耦的载体（宿主注入偏好、回调回写），
/// 因此 `==` / `hashCode` 必须正确：等值注入若被判为"不同"会触发无谓重建，
/// 而值变了却判为"相同"，播放器就会一直读旧偏好。
void main() {
  test('默认值：长按加速开启、倍率 2.0', () {
    const prefs = PlayerPreferences();

    expect(prefs.longPressBoostEnabled, isTrue);
    expect(prefs.longPressSpeed, equals(2.0));
  });

  test('copyWith 只覆盖传入字段', () {
    const prefs = PlayerPreferences();

    final faster = prefs.copyWith(longPressSpeed: 3.0);
    expect(faster.longPressSpeed, equals(3.0));
    expect(faster.longPressBoostEnabled, isTrue, reason: '未传入的字段保持原值');

    final disabled = prefs.copyWith(longPressBoostEnabled: false);
    expect(disabled.longPressBoostEnabled, isFalse);
    expect(disabled.longPressSpeed, equals(2.0));
  });

  test('同值相等且哈希一致', () {
    const a = PlayerPreferences(longPressSpeed: 5.0);
    const b = PlayerPreferences(longPressSpeed: 5.0);

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('任一字段不同即不相等', () {
    expect(
      const PlayerPreferences(longPressSpeed: 2.0),
      isNot(equals(const PlayerPreferences(longPressSpeed: 3.0))),
    );
    expect(
      const PlayerPreferences(longPressBoostEnabled: false),
      isNot(equals(const PlayerPreferences(longPressBoostEnabled: true))),
    );
  });
}
