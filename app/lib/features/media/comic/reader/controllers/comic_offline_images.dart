import 'package:fluxforge/app/di/di.dart';

/// 本地图片查找：`(bookId, 图片网络地址) → 本地沙盒路径 | null`
///
/// 由调用方注入，缺省走 [downloadService] 的真实索引 —— 与
/// `ChapterContentPipeline(parseRule: …)` 同一「默认实现在外、可注入可测」范式。
typedef ComicLocalImageLookup = Future<String?> Function(
  String bookId,
  String imageUrl,
);

/// 把已离线下载的漫画图片换成**本地沙盒路径**（未下载的原样保留）
///
/// ### 为什么必须共用一份
/// 图片类作品的两种形态都要做这件事，但发生在不同时机：
/// - **图集**：详情页把 detail 给出的图片本地化后交给阅读器；
/// - **漫画**：阅读宿主把**每章解析出来的**图片本地化。
///
/// 若各自实现，就会出现"图集能断网看、章节不能"的割裂 —— 同一本书两种体验。
///
/// 已经是本地路径（非 http）的地址原样返回，因此图集那条**已经本地化过**的链路
/// 再走一次也无副作用。
Future<List<String>> resolveComicOfflineImages(
  List<String> urls, {
  required String bookId,
  ComicLocalImageLookup? lookup,
}) async {
  if (urls.isEmpty || bookId.isEmpty) return urls;

  final resolve =
      lookup ??
      (String id, String url) => downloadService.localComicImagePath(id, url);

  return Future.wait(
    urls.map((url) async {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        return url;
      }
      try {
        final local = await resolve(bookId, url);
        return local ?? url;
      } catch (_) {
        // 索引不可用（如未完成初始化）时退回网络地址，绝不让阅读中断
        return url;
      }
    }),
  );
}
