import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/media/comic/reader/controllers/comic_offline_images.dart';

/// 漫画离线图片本地化（图集与章节形态共用）
void main() {
  test('已下载的换成本地路径，未下载的原样保留', () async {
    final result = await resolveComicOfflineImages(
      const ['https://cdn.a/1.jpg', 'https://cdn.a/2.jpg'],
      bookId: 'book-1',
      lookup: (bookId, url) async =>
          url.endsWith('1.jpg') ? '/sandbox/book-1/1.jpg' : null,
    );

    expect(result, ['/sandbox/book-1/1.jpg', 'https://cdn.a/2.jpg']);
  });

  test('本地路径原样返回且不查索引（图集链路已本地化，再走一次无副作用）', () async {
    var calls = 0;
    final result = await resolveComicOfflineImages(
      const ['/sandbox/book-1/1.jpg', 'file:///x/2.jpg'],
      bookId: 'book-1',
      lookup: (bookId, url) async {
        calls++;
        return null;
      },
    );

    expect(result, ['/sandbox/book-1/1.jpg', 'file:///x/2.jpg']);
    expect(calls, 0);
  });

  test('空列表 / 空 bookId 直接返回且不查索引', () async {
    var calls = 0;
    Future<String?> lookup(String bookId, String url) async {
      calls++;
      return null;
    }

    expect(
      await resolveComicOfflineImages(
        const ['https://cdn.a/1.jpg'],
        bookId: '',
        lookup: lookup,
      ),
      ['https://cdn.a/1.jpg'],
    );
    expect(
      await resolveComicOfflineImages(const [], bookId: 'book-1', lookup: lookup),
      isEmpty,
    );
    expect(calls, 0);
  });

  test('索引抛错时退回网络地址，绝不中断阅读', () async {
    final result = await resolveComicOfflineImages(
      const ['https://cdn.a/1.jpg'],
      bookId: 'book-1',
      lookup: (bookId, url) async => throw Exception('索引未初始化'),
    );

    expect(result, ['https://cdn.a/1.jpg']);
  });
}
