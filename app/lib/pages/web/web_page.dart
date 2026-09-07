import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class WebPage extends StatefulWidget {
  const WebPage({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {

  late final WebViewController _controller;
  String _title = '';
  bool _canGoBack = false;
  double _loadProgress = 0;

  @override
  void initState() {
    super.initState();

    _title = widget.title ?? '';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            _controller.canGoBack().then((value) {
              setState(() {
                _canGoBack = value;
              });
            });
          },
          onProgress: (int progress) {
            // 更新加载条
            setState(() {
              _loadProgress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _loadProgress = 0;
            });
            setTitle();
          },
          onPageFinished: (String url) {
            setTitle();
          },
          onHttpError: (HttpResponseError error) {},
          onWebResourceError: (WebResourceError error) {},
          // onNavigationRequest: (NavigationRequest request) async {
          //   final url = request.url;
          //   // 检查是否应该拦截
          //   if (AdBlockEngine.instance.shouldBlock(url)) {
          //     return NavigationDecision.prevent;
          //   }
            
          //   return NavigationDecision.navigate;
          // }
        ),
      )
      ..loadRequest(Uri.parse(widget.url));

      _setupAndroidFullscreen();
  }

  void _setupAndroidFullscreen() {
    final platform = _controller.platform;

    if (platform is AndroidWebViewController) {
      // 允许自动播放
      platform.setMediaPlaybackRequiresUserGesture(false);

      // 允许全屏
      platform.setCustomWidgetCallbacks(
        onShowCustomWidget: (Widget widget, OnHideCustomWidgetCallback callback) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => widget,
              fullscreenDialog: true,
            ),
          );
          // 横屏
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);

          // 沉浸式
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
        },
        onHideCustomWidget: () {
          Navigator.of(context).pop();
          // 恢复竖屏
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);

          // 恢复系统 UI
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge,
          );
        },
      );
    }
  }

  Widget _buildBottomSheet() {
    Widget buildButton({
      required String title,
      required IconData icon,
      Color iconColor = Colors.black87,
      void Function()? onTap
    }) {
      return GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 70,
          height: 100,
          child: Column(
            spacing: 6,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)
                ),
                child: Icon(icon, size: 28, color: iconColor),
              ),
              Text(title, style: TextStyle(fontSize: 11), textAlign: TextAlign.center),
            ],
          )
        ),
      );
    }


    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12),
      height: 200,
      child: Column(
        spacing: 12,
        children: [
          Row(
            spacing: 12,
            children: [
              buildButton(
                title: '刷新',
                icon: Icons.refresh_rounded,
                iconColor: Colors.blue,
                onTap: () {
                   Navigator.pop(context);
                  _controller.reload();
                },
              ),
              buildButton(
                title: '在浏览器打开',
                icon: Icons.open_in_browser_rounded,
                onTap: () {
                  Navigator.pop(context);
                  // 打开外部浏览器
                  launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
                },
              ),
              buildButton(
                title: '复制链接',
                icon: LucideIcons.copyPlus,
                onTap: () async {
                  Navigator.pop(context);
                  var url = await _controller.currentUrl();
                  await Clipboard.setData(ClipboardData(text: url ?? ''));
                },
              ),
            ],
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (_canGoBack) {
          _controller.goBack();
        } else {
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title),
          leadingWidth: 96,
          leading: Row(
            children: [
              BackButton(),
              Visibility(
                visible: _canGoBack,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    context.pop();
                  },
                )
              )
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded),
              onPressed: () {
                showModalBottomSheet(
                  isDismissible: true,
                  showDragHandle: true,
                  // showDragHandle: true,
                  context: context,
                  builder: (context) {
                    return BottomSheet(
                      onClosing: () {
                      
                      },
                      builder: (context) {
                        return _buildBottomSheet();
                      }
                    );
                  }
                );
              },
            )
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            Visibility(
              visible: _loadProgress < 1.0,
              child: LinearProgressIndicator(value: _loadProgress, minHeight: 2),
            ),
          ],
        ),
      )
    );
  }

  /// 设置标题
  void setTitle() {
    _controller.getTitle().then((value) {
      setState(() {
        _title = value ?? '';
      });
    });
  }

}