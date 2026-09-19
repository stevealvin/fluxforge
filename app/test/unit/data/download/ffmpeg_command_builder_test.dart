import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/data/download/ffmpeg_command_builder.dart';

void main() {
  group('buildDownload 命令构造', () {
    test('无请求头时输出完整的下载封装命令，且顺序符合 FFmpeg 作用域规则', () {
      final command = FfmpegCommandBuilder.buildDownload(
        url: 'https://cdn.example.com/hls/index.m3u8',
        outputPath: '/data/user/0/com.nl.fluxforge/files/videos/book/0.mp4',
      );

      expect(
        command,
        equals(
          '-y '
          '-protocol_whitelist "${FfmpegCommandBuilder.protocolWhitelist}" '
          '-i "https://cdn.example.com/hls/index.m3u8" '
          '-c copy -bsf:a aac_adtstoasc -movflags +faststart '
          '"/data/user/0/com.nl.fluxforge/files/videos/book/0.mp4"',
        ),
      );

      // 输入侧选项必须排在 -i 之前，输出侧选项必须排在 -i 之后
      final inputIndex = command.indexOf('-i "');
      expect(command.indexOf('-protocol_whitelist'), lessThan(inputIndex));
      expect(command.indexOf('-c copy'), greaterThan(inputIndex));
    });

    test('协议白名单必须包含 crypto，否则 AES-128 加密的 m3u8 无法下载', () {
      final command = FfmpegCommandBuilder.buildDownload(
        url: 'https://a/b.m3u8',
        outputPath: '/tmp/a.mp4',
      );
      expect(command, contains('crypto'));
      expect(command, contains('data'));
    });

    test('URL 中的 & 必须被引号包裹，否则会被拆成多个参数', () {
      final command = FfmpegCommandBuilder.buildDownload(
        url: 'https://a.com/v.m3u8?token=abc&sign=def&uid=1',
        outputPath: '/tmp/a.mp4',
      );
      expect(command, contains('-i "https://a.com/v.m3u8?token=abc&sign=def&uid=1"'));
    });

    test('输出路径含空格与中文时同样被引号包裹', () {
      final command = FfmpegCommandBuilder.buildDownload(
        url: 'https://a/b.m3u8',
        outputPath: '/tmp/my videos/第 1 集.mp4',
      );
      expect(command, contains('"/tmp/my videos/第 1 集.mp4"'));
    });

    test('路径或头值中的双引号被转义', () {
      final command = FfmpegCommandBuilder.buildDownload(
        url: 'https://a/b.m3u8',
        outputPath: '/tmp/say"hi".mp4',
      );
      expect(command, contains(r'"/tmp/say\"hi\".mp4"'));
    });

    test('本地 HLS 分片合并命令：协议白名单收窄且不再需要任何 HTTP 头', () {
      final command = FfmpegCommandBuilder.buildLocalMerge(
        playlistPath: '/data/videos/book/0/local.m3u8',
        outputPath: '/data/videos/book/0.mp4',
      );

      // 分片与密钥均已落盘，白名单不需要网络协议
      expect(command, contains('-protocol_whitelist "file,crypto,data"'));
      expect(command, isNot(contains('http')));
      expect(command, isNot(contains('-headers')));
      expect(command, contains('-i "/data/videos/book/0/local.m3u8"'));
      expect(command, contains('-bsf:a aac_adtstoasc'));
      expect(command, contains('-movflags +faststart'));
    });
  });

  group('buildHeaderArgs 请求头传递', () {
    test('无头时返回空列表，命令中不出现 -headers', () {
      expect(FfmpegCommandBuilder.buildHeaderArgs(const {}), isEmpty);

      final command = FfmpegCommandBuilder.buildDownload(
        url: 'https://a/b.m3u8',
        outputPath: '/tmp/a.mp4',
      );
      expect(command, isNot(contains('-headers')));
      expect(command, isNot(contains('-user_agent')));
    });

    test('User-Agent 与 Referer 走专用选项，不落进 -headers', () {
      final args = FfmpegCommandBuilder.buildHeaderArgs(const {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://a.com/',
      });

      expect(args, equals(['-user_agent', '"Mozilla/5.0"', '-referer', '"https://a.com/"']));
      expect(args.join(' '), isNot(contains('-headers')));
    });

    test('头名大小写不敏感，referrer 拼写同样被识别', () {
      final lower = FfmpegCommandBuilder.buildHeaderArgs(const {
        'user-agent': 'UA',
        'referrer': 'https://r.com/',
      });
      expect(lower, equals(['-user_agent', '"UA"', '-referer', '"https://r.com/"']));
    });

    test('Cookie 等其余头以 CRLF 分隔拼进 -headers 且末尾补 CRLF', () {
      final args = FfmpegCommandBuilder.buildHeaderArgs(const {
        'Cookie': 'sid=1; uid=2',
        'X-Token': 'abc',
      });

      expect(args.length, equals(2));
      expect(args.first, equals('-headers'));
      expect(args.last, equals('"Cookie: sid=1; uid=2\r\nX-Token: abc\r\n"'));
    });

    test('专用选项与 -headers 可共存，且专用选项在前', () {
      final args = FfmpegCommandBuilder.buildHeaderArgs(const {
        'Cookie': 'sid=1',
        'Referer': 'https://a.com/',
      });

      expect(args, equals(['-referer', '"https://a.com/"', '-headers', '"Cookie: sid=1\r\n"']));
    });

    test('空键或空值的头被丢弃，不污染命令', () {
      final args = FfmpegCommandBuilder.buildHeaderArgs(const {
        '': 'value',
        'Token': '',
        '   ': '   ',
        'Valid': 'yes',
      });

      expect(args, equals(['-headers', '"Valid: yes\r\n"']));
    });
  });

  group('parseDurationFromLog 总时长解析', () {
    test('解析标准摘要行', () {
      const line =
          '  Duration: 00:12:34.56, start: 0.000000, bitrate: 1234 kb/s';
      final duration = FfmpegCommandBuilder.parseDurationFromLog(line);

      expect(duration, equals(const Duration(minutes: 12, seconds: 34, milliseconds: 560)));
    });

    test('小数位为 1 位或 2 位时按毫秒右补齐，而不是当成个位毫秒', () {
      expect(
        FfmpegCommandBuilder.parseDurationFromLog('Duration: 00:00:01.5, x'),
        equals(const Duration(seconds: 1, milliseconds: 500)),
      );
      expect(
        FfmpegCommandBuilder.parseDurationFromLog('Duration: 00:00:01.25, x'),
        equals(const Duration(seconds: 1, milliseconds: 250)),
      );
    });

    test('小时位大于 1 位、无 Duration 行时分别正确解析与返回 null', () {
      expect(
        FfmpegCommandBuilder.parseDurationFromLog('Duration: 123:00:05.000, x'),
        equals(const Duration(hours: 123, seconds: 5)),
      );
      expect(
        FfmpegCommandBuilder.parseDurationFromLog('frame= 100 fps=30 q=-1.0'),
        isNull,
      );
    });

    test('Duration 为 N/A（直播流）时返回 null', () {
      expect(
        FfmpegCommandBuilder.parseDurationFromLog('Duration: N/A, start: 0.000000'),
        isNull,
      );
    });
  });

  group('progressRatio 进度换算', () {
    test('总时长未知时返回 null，绝不伪造 0.0', () {
      expect(
        FfmpegCommandBuilder.progressRatio(processedMillis: 5000, totalDuration: null),
        isNull,
      );
      expect(
        FfmpegCommandBuilder.progressRatio(
          processedMillis: 5000,
          totalDuration: Duration.zero,
        ),
        isNull,
      );
    });

    test('按已处理时长占总时长的比例计算', () {
      expect(
        FfmpegCommandBuilder.progressRatio(
          processedMillis: 30 * 1000,
          totalDuration: const Duration(minutes: 1),
        ),
        closeTo(0.5, 0.0001),
      );
    });

    test('超出或为负时被 clamp 到 0.0 ~ 1.0', () {
      expect(
        FfmpegCommandBuilder.progressRatio(
          processedMillis: 999 * 1000,
          totalDuration: const Duration(minutes: 1),
        ),
        equals(1.0),
      );
      expect(
        FfmpegCommandBuilder.progressRatio(
          processedMillis: -100,
          totalDuration: const Duration(minutes: 1),
        ),
        equals(0.0),
      );
    });
  });
}
