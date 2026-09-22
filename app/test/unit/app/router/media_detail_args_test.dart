import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/app/router/route_args.dart';
import 'package:fluxforge/domain/rule/rule.dart';

/// 通用媒体详情参数必须能携带规则
///
/// 详情页拿不到规则时会退化到「按 URL host 反查」→「`rules.first` 随便挑一条」，
/// 后者会让 baseUrl 错位（相对地址补全、请求头全会跟着错）。
/// 历史页的兜底分支此前就传不了规则，这里锁住这个契约。
void main() {
  final rule = Rule(
    id: 3,
    name: '图源',
    baseUrl: 'https://example.com',
    type: 'comic',
    code: '// noop',
  );

  test('构造时携带规则，并可直接取回', () {
    final args = MediaDetailArgs(
      title: '测试',
      url: 'https://example.com/detail/1',
      rule: rule,
    );

    expect(args.rule, same(rule));
    expect(MediaDetailArgs.tryParse(args)?.rule, same(rule));
  });

  test('从 Map 还原时同样能解析出规则', () {
    final parsed = MediaDetailArgs.tryParse({
      'title': '测试',
      'url': 'https://example.com/detail/1',
      'type': 'comic',
      'rule': {
        'id': 3,
        'name': '图源',
        'baseUrl': 'https://example.com',
        'type': 'comic',
        'code': '// noop',
      },
    });

    expect(parsed?.rule?.baseUrl, 'https://example.com');
    expect(parsed?.type, 'comic');
  });

  test('不传规则时保持为 null（由详情页自行兜底）', () {
    expect(MediaDetailArgs(title: '测试', url: 'u').rule, isNull);
  });
}
