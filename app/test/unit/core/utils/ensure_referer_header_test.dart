import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/core/utils/media_utils.dart';

/// 图片 Referer 兜底
///
/// 实测依据：同一图床，不带 Referer → 403，带任意 Referer → 200（UA 不参与判定）。
/// 因此契约是「**请求至少要有一个 Referer**」，同时绝不覆盖调用方给的值。
void main() {
  const imageUrl =
      'https://p11.mmdb.cc/file/20230325/235677054302/00579195.jpg';

  test('完全没带头时，补上图片自身的站点根', () {
    final result = ensureRefererHeader(imageUrl, null);

    expect(result?['Referer'], 'https://p11.mmdb.cc');
  });

  test('已有其它头时保留它们，并追加 Referer', () {
    final result = ensureRefererHeader(imageUrl, const {'Cookie': 'a=1'});

    expect(result?['Cookie'], 'a=1');
    expect(result?['Referer'], 'https://p11.mmdb.cc');
  });

  test('调用方已给 Referer 时原样返回，不覆盖（大小写不敏感）', () {
    const headers = {'referer': 'https://meirentu.cc'};

    final result = ensureRefererHeader(imageUrl, headers);

    expect(identical(result, headers), isTrue, reason: '无需补时直接返回入参');
    expect(result!['Referer'], isNull, reason: '不能写出第二个 Referer 键');
  });

  test('非绝对地址不补（拿不到站点根，补错不如不补）', () {
    expect(ensureRefererHeader('/file/a.jpg', null), isNull);
    expect(ensureRefererHeader('', null), isNull);
  });

  test('纯函数：不改动入参', () {
    final input = <String, String>{'Cookie': 'a=1'};

    ensureRefererHeader(imageUrl, input);

    expect(input.length, 1, reason: '入参不被就地写入 Referer');
  });
}
