/// 翻页模式
enum PageTurnMode {
  horizontal('平滑横翻'),
  verticalScroll('上下滚动');

  const PageTurnMode(this.label);

  /// 用于设置面板展示的中文名称
  final String label;
}
