import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/routes/app_navigation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用内网页搜索页：在 WebView 中打开平台搜索页（桌面版 UA），
/// 页面导航到直播间链接时在底部提示条中一键回跳应用内播放。
///
/// 回跳识别复用 [LiveUrlTool.parseLiveUrl]（覆盖五平台的直播间链接样式，
/// 包括分享短链）；识别失败的页面只是不显示提示条，浏览不受影响。
class WebSearchPage extends StatefulWidget {
  const WebSearchPage({super.key});

  @override
  State<WebSearchPage> createState() => _WebSearchPageState();
}

class _WebSearchPageState extends State<WebSearchPage> {
  InAppWebViewController? _webController;
  Uri? _requestUrl;
  String _platform = '';
  String _keyword = '';
  String _currentUrl = '';
  String? _foundRoomId;
  String? _foundRoomPlatform;
  bool _dismissedForCurrentRoom = false;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map) {
      _requestUrl = Uri.tryParse(args['url']?.toString() ?? '');
      _platform = args['platform']?.toString() ?? '';
      _keyword = args['keyword']?.toString() ?? '';
    }
  }

  Future<void> _checkRoomLink(String url) async {
    if (url == _currentUrl) return;
    _currentUrl = url;
    List<String> parsed;
    try {
      parsed = await LiveUrlTool.parseLiveUrl(url);
    } catch (_) {
      parsed = const [];
    }
    if (!mounted) return;
    final hasRoom = parsed.length >= 2 && parsed.first.isNotEmpty;
    setState(() {
      _foundRoomId = hasRoom ? parsed.first : null;
      _foundRoomPlatform = hasRoom ? parsed[1] : null;
      _dismissedForCurrentRoom = false;
    });
  }

  void _openFoundRoom() {
    final roomId = _foundRoomId;
    final platform = _foundRoomPlatform;
    if (roomId == null || platform == null || roomId.isEmpty) return;
    AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(
        roomId: roomId,
        platform: platform,
        title: '',
        cover: '',
        nick: '',
        watching: '',
        avatar: '',
        area: '',
        liveStatus: LiveStatus.live,
        status: true,
        data: '',
        danmakuData: '',
      ),
    );
  }

  Future<void> _openExternal() async {
    final url = Uri.tryParse(_currentUrl.isNotEmpty ? _currentUrl : (_requestUrl?.toString() ?? ''));
    if (url != null) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _keyword.isEmpty ? i18n('web_search_title') : '${_platform.toUpperCase()} · $_keyword',
          style: const TextStyle(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            // 先退 WebView 页内历史，第一页才关闭路由。
            if (await _webController?.canGoBack() ?? false) {
              await _webController?.goBack();
              return;
            }
            if (Navigator.canPop(context)) Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            tooltip: i18n('web_search_open_external'),
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _openExternal,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _requestUrl == null
                ? const SizedBox.shrink()
                : InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_requestUrl.toString())),
              initialSettings: InAppWebViewSettings(
                userAgent:
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
                useShouldOverrideUrlLoading: false,
                javaScriptEnabled: true,
              ),
              onWebViewCreated: (controller) => _webController = controller,
              onLoadStop: (controller, url) {
                if (url != null) _checkRoomLink(url.toString());
              },
              onUpdateVisitedHistory: (controller, url, isReload) {
                if (url != null && isReload != true) _checkRoomLink(url.toString());
              },
            ),
          ),
          if (_foundRoomId != null && !_dismissedForCurrentRoom)
            SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i18n('web_search_room_found', args: {
                          'platform': (_foundRoomPlatform ?? '').toUpperCase(),
                          'id': _foundRoomId ?? '',
                        }),
                        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _openFoundRoom,
                      child: Text(i18n('web_search_open_room'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _dismissedForCurrentRoom = true),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
