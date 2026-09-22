import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/data/download/hls_playlist_parser.dart';

void main() {
  const base = 'https://cdn.example.com/live/2024/';
  final baseUri = Uri.parse(base);

  test('media playlist：相对路径分片按清单所在目录绝对化', () {
    const text =
        '#EXTM3U\n#EXTINF:9.009,\nseg0.ts\n#EXTINF:9.009,\n../parts/seg1.ts\n';
    final playlist = HlsPlaylistParser.parse(text, baseUri);

    expect(playlist.isMaster, isFalse);
    expect(
      playlist.segmentUrls,
      equals(['${base}seg0.ts', 'https://cdn.example.com/live/parts/seg1.ts']),
    );
    expect(playlist.resourceUrls, equals(playlist.segmentUrls));
  });

  test('AES-128 加密清单把密钥一并纳入本地化资源（解密交给 FFmpeg）', () {
    const text =
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin",IV=0x1\n#EXTINF:6.0,\nseg0.ts\n';
    final playlist = HlsPlaylistParser.parse(text, baseUri);

    expect(
      playlist.resourceUrls,
      containsAll(['${base}keys/key.bin', '${base}seg0.ts']),
    );
    // 密钥不计入分片序列
    expect(playlist.segmentUrls, equals(['${base}seg0.ts']));
  });

  test('EXT-X-MAP 初始化段同样纳入本地化资源', () {
    const text = '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4.0,\nseg0.m4s\n';
    final playlist = HlsPlaylistParser.parse(text, baseUri);

    expect(
      playlist.resourceUrls,
      containsAll(['${base}init.mp4', '${base}seg0.m4s']),
    );
  });

  test('CRLF 换行、行首尾空白与空行不影响解析', () {
    const text = '#EXTM3U\r\n#EXTINF:5.0,\r\n  seg0.ts  \r\n\r\nseg1.ts\r\n';
    final playlist = HlsPlaylistParser.parse(text, baseUri);

    expect(playlist.segmentUrls, equals(['${base}seg0.ts', '${base}seg1.ts']));
  });

  test('data: 内联密钥无需下载', () {
    const text =
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="data:text/plain;base64,AAAA"\n#EXTINF:5.0,\nseg0.ts\n';
    final playlist = HlsPlaylistParser.parse(text, baseUri);

    expect(playlist.resourceUrls, equals(['${base}seg0.ts']));
  });

  test('master playlist：变体归入 variantUrls 而非 segmentUrls', () {
    const text =
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000\n720p.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=640000\n480p.m3u8\n';
    final playlist = HlsPlaylistParser.parse(text, baseUri);

    expect(playlist.isMaster, isTrue);
    expect(
      playlist.variantUrls,
      equals(['${base}720p.m3u8', '${base}480p.m3u8']),
    );
    expect(playlist.segmentUrls, isEmpty);
    expect(playlist.resourceUrls, equals(playlist.variantUrls));
  });

  test('rewriteToLocal：分片行与 KEY 属性中的 URI 都被替换为本地相对路径', () {
    const text =
        '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin",IV=0x1\n#EXTINF:6.0,\nseg0.ts\n';
    final mapping = {
      '${base}keys/key.bin': 'key_0000.bin',
      '${base}seg0.ts': 'seg_0000.ts',
    };

    final rewritten = HlsPlaylistParser.rewriteToLocal(text, baseUri, mapping);

    expect(rewritten, contains('URI="key_0000.bin"'));
    expect(rewritten, isNot(contains('keys/key.bin')));
    expect(rewritten, contains('seg_0000.ts'));
    // 未在映射中的行保持原样
    expect(rewritten, contains('#EXTINF:6.0,'));
  });

  test('rewriteToLocal：映射为空时原样返回；未命中的行不被破坏', () {
    const text = '#EXTM3U\n#EXTINF:6.0,\nseg0.ts\n';
    expect(
      HlsPlaylistParser.rewriteToLocal(text, baseUri, const {}),
      equals(text),
    );

    final rewritten = HlsPlaylistParser.rewriteToLocal(text, baseUri, {
      '${base}other.ts': 'other_0000',
    });
    expect(rewritten, contains('seg0.ts'));
  });
}
