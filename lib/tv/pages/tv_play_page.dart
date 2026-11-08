import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/states/load_type.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:qr_flutter/qr_flutter.dart' show QrVersions;

import '../core/tv_device_service.dart';
import '../core/tv_theme.dart';
import '../widgets/tv_widgets.dart';

/// TV 播放页（严格对齐 pure_live_TV 播放界面）：
///
/// - 视频恒全屏；顶部信息卡（进房先显示：标题/平台/主播/热度/时钟，自动隐藏）；
/// - 底部控制栏 = 索引模型（OK 呼出，←→ 移动，OK 激活，↑↓ 换台不抢）；
/// - 右侧浮层面板 = 索引选择（播放列表 / 清晰度 / 线路 / 弹幕）；
/// - 键位状态机：无浮层 OK→控制栏、↑↓→换台(300ms 防抖)、←→双击关注、→→播放列表；
///   Back 分级退出：面板 → 控制栏 → 信息卡 → 离开页面。
/// - 换台横幅：切台时顶部显示频道名。
class TvPlayPage extends StatefulWidget {
  const TvPlayPage({
    super.key,
    required this.room,
    required this.rooms,
    this.initialIndex = 0,
  });

  final LiveRoom room;
  final List<LiveRoom> rooms;
  final int initialIndex;

  /// 最近的房间（宿主在页面 pop 后同步网格高亮用）
  static LiveRoom? lastRoom;

  @override
  State<TvPlayPage> createState() => _TvPlayPageState();
}

/// 创建并登记直播页控制器（等价手机端 LivePlayBinding 的手动版）。
/// 失败（TV 进程缺某服务）时抛出，由调用方决定兜底。
void tvEnsureLivePlayController(LiveRoom room) {
  if (Get.isRegistered<LivePlayController>()) {
    Get.delete<LivePlayController>(force: true);
  }
  Get.put(LivePlayController(room: room, site: room.platform ?? ''));
}

/// TV 换台：销毁旧控制器并以新房间重建播放页（pushReplacement，
/// 与手机端"切台=route replace"同策略），避免播放器双实例。
void tvReplacePlayRoute(LiveRoom newRoom, List<LiveRoom> rooms) {
  tvEnsureLivePlayController(newRoom);
  final context = Get.context;
  if (context != null) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TvPlayPage(room: newRoom, rooms: rooms)),
    );
  }
}

enum _TvZone { none, bar, panel }

enum _TvPanel { playlist, quality, line, danmaku }

class _TvPlayPageState extends State<TvPlayPage> {
  late LiveRoom _currentRoom;
  _TvZone _zone = _TvZone.none;
  _TvPanel _panel = _TvPanel.playlist;
  int _panelIndex = 0;
  int _barIndex = 0;
  bool _showRoomInfo = true;
  bool _showBar = false;
  String _banner = '';
  Timer? _bannerTimer;
  Timer? _infoTimer;
  Timer? _channelTimer;
  int _channelDelta = 0;
  DateTime _lastLeftAt = DateTime.fromMillisecondsSinceEpoch(0);
  final ScrollController _panelScroll = ScrollController();

  /// 底部控制栏条目索引
  static const int _kPlayPause = 0,
      _kQuality = 1,
      _kLine = 2,
      _kFit = 3,
      _kDanmaku = 4,
      _kRefresh = 5,
      _kFollow = 6;

  LivePlayController get _ctrl => Get.find<LivePlayController>();
  LivePlayState get _state => _ctrl.state.value;
  VideoController? get _videoController => _state.player.videoController;
  List<BoxFit> get _fitList => SettingsService.to.player.videoFitArray;

  bool get _followed => SettingsService.to.fav.isFavorite(_currentRoom);

  @override
  void initState() {
    super.initState();
    _currentRoom = widget.room;
    TvPlayPage.lastRoom = _currentRoom;
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);
    TvDeviceService.setMenuKeyHandler(_toggleUi);
    _scheduleInfoHide();
    _scrollPanelToCurrent();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    TvDeviceService.setMenuKeyHandler(null);
    _bannerTimer?.cancel();
    _infoTimer?.cancel();
    _channelTimer?.cancel();
    _panelScroll.dispose();
    // 退出播放页：先显式停掉播放器（声音立即停），再销毁控制器。
    // 换台（pushReplacement）时新控制器已换成新房间，身份不匹配则不删。
    unawaited(GlobalPlayerService.instance.playerManager.stop());
    try {
      if (Get.isRegistered<LivePlayController>()) {
        final ctrl = Get.find<LivePlayController>();
        if (ctrl.room.hasSameIdentity(_currentRoom)) {
          Get.delete<LivePlayController>(force: true);
        }
      }
    } catch (e) {
      debugPrint('[TvPlay] dispose controller error: $e');
    }
    super.dispose();
  }

  void _scheduleInfoHide() {
    _infoTimer?.cancel();
    _infoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && _showRoomInfo && _zone != _TvZone.none) return;
      if (mounted && _showRoomInfo) setState(() => _showRoomInfo = false);
    });
  }

  // ---------------------------------------------------------------------------
  // 按键（全局 handler：注册早于播放页内部，必然先收到）
  // ---------------------------------------------------------------------------

  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final confirm = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;

    try {
      // 菜单键：呼出/退出整个 UI（控制栏+面板）
      if (key == LogicalKeyboardKey.contextMenu) {
        _toggleUi();
        return true;
      }
      if (confirm) return _onOk();
      if (key == LogicalKeyboardKey.arrowUp) return _onVertical(-1);
      if (key == LogicalKeyboardKey.arrowDown) return _onVertical(1);
      if (key == LogicalKeyboardKey.arrowLeft) return _onLeft();
      if (key == LogicalKeyboardKey.arrowRight) return _onRight();
      if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) return _onBack();
    } catch (e) {
      debugPrint('[TvPlay] key handler error: $e');
    }
    return false;
  }

  bool _onOk() {
    debugPrint('[TvPlay] onOk zone=$_zone bar=$_barIndex panel=$_panel');
    switch (_zone) {
      case _TvZone.none:
        setState(() {
          _zone = _TvZone.bar;
          _showBar = true;
          _showRoomInfo = false;
          _barIndex = _kPlayPause;
        });
        return true;
      case _TvZone.bar:
        _activateBar();
        return true;
      case _TvZone.panel:
        _activatePanel();
        return true;
    }
  }

  bool _onVertical(int delta) {
    debugPrint('[TvPlay] onVertical $delta zone=$_zone bar=$_barIndex');
    switch (_zone) {
      case _TvZone.none:
      case _TvZone.bar:
        // 无浮层/控制栏：↑↓ 换台（300ms 防抖合并，一次提交）
        _queueChannel(delta);
        return true;
      case _TvZone.panel:
        setState(() {
          _panelIndex = (_panelIndex + delta).clamp(0, _panelLength() - 1);
        });
        _ensurePanelVisible();
        return true;
    }
  }

  bool _onLeft() {
    switch (_zone) {
      case _TvZone.none:
        // 双击关注/取关（500ms 双击窗），单击提示
        final now = DateTime.now();
        if (now.difference(_lastLeftAt) <= const Duration(milliseconds: 500)) {
          _lastLeftAt = DateTime.fromMillisecondsSinceEpoch(0);
          _toggleFollow();
        } else {
          _lastLeftAt = now;
          _showBanner(_followed ? '再按一次← 取消关注' : '再按一次← 关注主播');
        }
        return true;
      case _TvZone.bar:
        setState(() {
          _barIndex = (_barIndex - 1).clamp(0, _kFollow);
        });
        return true;
      case _TvZone.panel:
        _closePanel();
        return true;
    }
  }

  bool _onRight() {
    switch (_zone) {
      case _TvZone.none:
        _openPanel(_TvPanel.playlist);
        return true;
      case _TvZone.bar:
        setState(() {
          _barIndex = (_barIndex + 1).clamp(0, _kFollow);
        });
        return true;
      case _TvZone.panel:
        _closePanel();
        return true;
    }
  }

  /// 菜单键：UI 可见→整体隐藏；隐藏→呼出控制栏
  void _toggleUi() {
    setState(() {
      if (_zone == _TvZone.none && !_showBar) {
        _zone = _TvZone.bar;
        _showBar = true;
        _showRoomInfo = false;
        _barIndex = _kPlayPause;
      } else {
        _zone = _TvZone.none;
        _showBar = false;
      }
    });
  }

  bool _onBack() {
    switch (_zone) {
      case _TvZone.panel:
      case _TvZone.bar:
        // UI 可见时返回 = 先退出整个 UI
        setState(() {
          _zone = _TvZone.none;
          _showBar = false;
        });
        return true;
      case _TvZone.none:
        if (_showRoomInfo) {
          setState(() => _showRoomInfo = false);
          return true;
        }
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
        return true;
    }
  }

  // ---------------------------------------------------------------------------
  // 控制栏动作
  // ---------------------------------------------------------------------------

  void _activateBar() {
    debugPrint('[TvPlay] activateBar $_barIndex');
    switch (_barIndex) {
      case _kPlayPause:
        GlobalPlayerService.instance.playerManager.togglePlayPause(source: 'tv.remote.ok');
        if (mounted) setState(() {});
        break;
      case _kQuality:
        _openPanel(_TvPanel.quality);
        break;
      case _kLine:
        _openPanel(_TvPanel.line);
        break;
      case _kFit:
        final manager = GlobalPlayerService.instance.playerManager;
        manager.changeVideoFit((manager.videoFitIndex.value + 1) % _fitList.length);
        _showBanner('画面比例：${_fitName(manager.videoFitIndex.value)}');
        if (mounted) setState(() {});
        break;
      case _kDanmaku:
        final dm = SettingsService.to.danmaku;
        dm.enableDanmakuDisplay.v = !dm.enableDanmakuDisplay.v;
        _showBanner(dm.enableDanmakuDisplay.v ? '弹幕已开启' : '弹幕已关闭');
        if (mounted) setState(() {});
        break;
      case _kRefresh:
        _videoController?.refresh();
        _showBanner('刷新播放');
        break;
      case _kFollow:
        _toggleFollow();
        break;
    }
  }

  String _fitName(int index) {
    final names = ['contain', 'fill', 'cover', '16:9', '4:3'];
    return index >= 0 && index < names.length ? names[index] : '$index';
  }

  void _toggleFollow() {
    final fav = SettingsService.to.fav;
    if (fav.isFavorite(_currentRoom)) {
      fav.removeRoom(_currentRoom);
      _showBanner('已取消关注 ${_currentRoom.nick ?? ''}');
    } else {
      fav.addRoom(_currentRoom);
      _showBanner('已关注 ${_currentRoom.nick ?? ''}');
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // 面板
  // ---------------------------------------------------------------------------

  int _panelLength() {
    switch (_panel) {
      case _TvPanel.playlist:
        return widget.rooms.isEmpty ? 1 : widget.rooms.length;
      case _TvPanel.quality:
        return (_state.player.qualites.isEmpty ? 1 : _state.player.qualites.length);
      case _TvPanel.line:
        return (_state.player.playUrls.isEmpty ? 1 : _state.player.playUrls.length);
      case _TvPanel.danmaku:
        return 1;
    }
  }

  void _openPanel(_TvPanel kind) {
    debugPrint('[TvPlay] openPanel $kind');
    setState(() {
      _panel = kind;
      _zone = _TvZone.panel;
      _showBar = false;
      _panelIndex = _initialPanelIndex(kind).clamp(0, _panelLength() - 1);
    });
    _scrollPanelToCurrent();
  }

  int _initialPanelIndex(_TvPanel kind) {
    switch (kind) {
      case _TvPanel.playlist:
        return widget.rooms.indexWhere((r) => r.hasSameIdentity(_currentRoom));
      case _TvPanel.quality:
        return _state.player.currentQuality;
      case _TvPanel.line:
        return _state.player.currentLineIndex;
      case _TvPanel.danmaku:
        return 0;
    }
  }

  void _closePanel() {
    setState(() {
      _zone = _TvZone.bar;
      _showBar = true;
    });
  }

  void _activatePanel() {
    switch (_panel) {
      case _TvPanel.playlist:
        final rooms = widget.rooms;
        if (rooms.isEmpty || _panelIndex >= rooms.length) return;
        final target = rooms[_panelIndex];
        if (target.hasSameIdentity(_currentRoom)) return;
        _switchToRoom(target);
        break;
      case _TvPanel.quality:
        final qualities = _state.player.qualites;
        if (qualities.isEmpty || _panelIndex >= qualities.length) return;
        _ctrl.setResolution(ReloadDataType.refreash, _panelIndex, _state.player.currentLineIndex);
        _showBanner('清晰度：${qualities[_panelIndex].quality}');
        _closePanel();
        break;
      case _TvPanel.line:
        final lines = _state.player.playUrls;
        if (lines.isEmpty || _panelIndex >= lines.length) return;
        _ctrl.setResolution(ReloadDataType.changeLine, _state.player.currentQuality, _panelIndex);
        _showBanner('线路 ${_panelIndex + 1}');
        _closePanel();
        break;
      case _TvPanel.danmaku:
        break;
    }
  }

  void _ensurePanelVisible() {
    if (!_panelScroll.hasClients) return;
    const rowH = 64.0;
    final viewport = _panelScroll.position.viewportDimension;
    final target = _panelIndex * rowH;
    final max = _panelScroll.position.maxScrollExtent;
    if (target < _panelScroll.offset) {
      _panelScroll.animateTo((target - rowH).clamp(0.0, max),
          duration: TvTheme.pageTransitionDuration, curve: TvTheme.focusCurve);
    } else if (target + rowH > _panelScroll.offset + viewport) {
      _panelScroll.animateTo((target + rowH - viewport).clamp(0.0, max),
          duration: TvTheme.pageTransitionDuration, curve: TvTheme.focusCurve);
    }
  }

  void _scrollPanelToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePanelVisible());
  }

  // ---------------------------------------------------------------------------
  // 换台（300ms 防抖 + 横幅）
  // ---------------------------------------------------------------------------

  void _queueChannel(int delta) {
    _channelDelta += delta;
    _channelTimer?.cancel();
    _channelTimer = Timer(const Duration(milliseconds: 300), () {
      final d = _channelDelta;
      _channelDelta = 0;
      if (d != 0) _switchChannel(d);
    });
  }

  void _switchChannel(int delta) {
    final rooms = widget.rooms;
    if (rooms.isEmpty) return;
    var idx = rooms.indexWhere((r) => r.hasSameIdentity(_currentRoom));
    idx = (idx + delta) % rooms.length;
    final target = rooms[idx < 0 ? idx + rooms.length : idx];
    if (target.hasSameIdentity(_currentRoom)) return;
    _switchToRoom(target);
  }

  void _switchToRoom(LiveRoom target) {
    _currentRoom = target;
    TvPlayPage.lastRoom = target;
    tvReplacePlayRoute(target, widget.rooms);
    _showBanner('${target.nick?.isNotEmpty == true ? target.nick : target.roomId}');
    _panelIndex = _initialPanelIndex(_panel).clamp(0, _panelLength() - 1);
    _scrollPanelToCurrent();
    if (mounted) setState(() {});
  }

  void _showBanner(String text) {
    setState(() => _banner = text);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _banner = '');
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final manager = GlobalPlayerService.instance.playerManager;
    // 键位处理只走全局 HardwareKeyboard handler（唯一入口）：
    // 若 Focus.onKeyEvent 也路由到 _globalKeyHandler，一次按键会触发两次
    // （全局 + 焦点链），表现为"索引跳两格/面板开了又关"。
    return Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 全屏视频（含音频模式 UI）
            ValueListenableBuilder<int>(
              valueListenable: manager.videoFitIndex,
              builder: (context, fitIndex, _) => manager.getVideoWidget(fitIndex, fitList: _fitList),
            ),
            // TV 弹幕飘屏（顶部 1/3 区域滚动）
            const Positioned.fill(child: _TvDanmakuOverlay()),
            // 顶部信息卡
            if (_showRoomInfo) _buildInfoCard(context),
            // 换台横幅
            if (_banner.isNotEmpty)
              Positioned(
                top: context.tvDp(20),
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: context.tvDp(18), vertical: context.tvDp(8)),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(context.tvDp(999)),
                      border: Border.all(color: TvTheme.focusColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(_banner, style: TextStyle(fontSize: context.tvSp(16), color: Colors.white)),
                  ),
                ),
              ),
            // 右侧浮层面板
            if (_zone == _TvZone.panel) _buildPanel(context),
            // 底部控制栏
            if (_showBar) _buildControlBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final detail = _state.room.detail;
    final title = detail?.title?.isNotEmpty == true ? detail!.title! : (_currentRoom.title ?? '');
    final nick = detail?.nick?.isNotEmpty == true ? detail!.nick! : (_currentRoom.nick ?? '');
    final platform = (_currentRoom.platform ?? '').toUpperCase();
    final heat = (detail?.watching?.isNotEmpty == true)
        ? detail!.watching!
        : (detail?.popularity?.isNotEmpty == true ? detail!.popularity! : '');
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(context.tvDp(20), context.tvDp(12), context.tvDp(20), context.tvDp(10)),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent]),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: context.tvSp(20), fontWeight: FontWeight.w700, color: Colors.white)),
                  SizedBox(height: context.tvDp(4)),
                  Text('$platform · $nick${heat.isEmpty ? '' : ' · 热度 $heat'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: context.tvSp(14), color: Colors.white70)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${two(now.hour)}:${two(now.minute)}',
                    style: TextStyle(
                        fontSize: context.tvSp(20), fontWeight: FontWeight.w700, color: Colors.white)),
                SizedBox(height: context.tvDp(2)),
                Text('$_followedText',
                    style: TextStyle(fontSize: context.tvSp(12), color: Colors.white70)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String get _followedText => _followed ? '已关注 · 按←双击取消' : '未关注 · 按←双击关注';

  Widget _buildControlBar(BuildContext context) {
    final items = <(IconData, String)>[
      (Icons.play_circle_fill_rounded, '播放/暂停'),
      (Icons.high_quality_rounded, '清晰度'),
      (Icons.alt_route_rounded, '线路'),
      (Icons.aspect_ratio_rounded, '画面比例'),
      (Icons.subtitles_rounded, '弹幕'),
      (Icons.refresh_rounded, '刷新'),
      (Icons.favorite_rounded, _followed ? '取消关注' : '关注'),
    ];
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(context.tvDp(16), context.tvDp(8), context.tvDp(16), context.tvDp(12)),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent]),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < items.length; i++)
              _BarItem(
                icon: items[i].$1,
                label: items[i].$2,
                active: _zone == _TvZone.bar && _barIndex == i,
                onTap: () {
                  setState(() {
                    _zone = _TvZone.bar;
                    _showBar = true;
                    _barIndex = i;
                  });
                  _activateBar();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final title = switch (_panel) {
      _TvPanel.playlist => '播放列表',
      _TvPanel.quality => '清晰度',
      _TvPanel.line => '线路',
      _TvPanel.danmaku => '弹幕',
    };
    return Positioned(
      top: context.tvDp(12),
      right: context.tvDp(12),
      bottom: context.tvDp(12),
      width: context.tvDp(400),
      child: Container(
        padding: EdgeInsets.all(context.tvDp(12)),
        decoration: BoxDecoration(
          color: TvTheme.background.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(context.tvDp(TvTheme.panelRadius)),
          border: Border.all(color: TvTheme.focusColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.tvDp(6), vertical: context.tvDp(4)),
              child: Text(title,
                  style: TextStyle(
                      fontSize: context.tvSp(18), fontWeight: FontWeight.w700, color: TvTheme.textPrimary)),
            ),
            SizedBox(height: context.tvDp(6)),
            Expanded(child: _buildPanelBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelBody(BuildContext context) {
    switch (_panel) {
      case _TvPanel.playlist:
        return _buildPlaylist(context);
      case _TvPanel.quality:
        return _buildQualityList(context);
      case _TvPanel.line:
        return _buildLineList(context);
      case _TvPanel.danmaku:
        return _buildDanmakuList(context);
    }
  }

  Widget _panelRow({
    required bool active,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: context.tvDp(4)),
        padding: EdgeInsets.symmetric(horizontal: context.tvDp(12), vertical: context.tvDp(12)),
        decoration: BoxDecoration(
          color: active ? TvTheme.focusColor : TvTheme.subtleFill,
          borderRadius: BorderRadius.circular(context.tvDp(10)),
          border: active ? Border.all(color: Colors.white70) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: context.tvSp(15),
                          fontWeight: FontWeight.w600,
                          color: active ? Colors.white : TvTheme.textPrimary)),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: context.tvSp(12),
                            color: active ? Colors.white70 : TvTheme.textSecondary)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylist(BuildContext context) {
    final rooms = widget.rooms;
    if (rooms.isEmpty) return TvEmpty(message: '暂无房间');
    return ListView.builder(
      controller: _panelScroll,
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        final active = index == _panelIndex;
        final live = room.liveStatus == LiveStatus.live && room.status == true;
        return _panelRow(
          active: active,
          label: room.nick?.isNotEmpty == true ? room.nick! : (room.roomId ?? ''),
          subtitle: '${(room.platform ?? '').toUpperCase()}${live ? " · 直播中" : ""}',
          onTap: () {
            setState(() => _panelIndex = index);
            _activatePanel();
          },
          trailing: live
              ? Icon(Icons.circle, size: context.tvDp(10), color: Colors.redAccent)
              : null,
        );
      },
    );
  }

  Widget _buildQualityList(BuildContext context) {
    final qualities = _state.player.qualites;
    if (qualities.isEmpty) return TvEmpty(message: '清晰度加载中...');
    return ListView.builder(
      controller: _panelScroll,
      itemCount: qualities.length,
      itemBuilder: (context, index) {
        final active = index == _panelIndex;
        final current = index == _state.player.currentQuality;
        return _panelRow(
          active: active,
          label: qualities[index].quality,
          subtitle: current ? '当前' : null,
          onTap: () {
            setState(() => _panelIndex = index);
            _activatePanel();
          },
          trailing: current
              ? Icon(Icons.check_rounded, size: context.tvDp(18), color: TvTheme.focusColor)
              : null,
        );
      },
    );
  }

  Widget _buildLineList(BuildContext context) {
    final lines = _state.player.playUrls;
    if (lines.isEmpty) return TvEmpty(message: '线路加载中...');
    return ListView.builder(
      controller: _panelScroll,
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final active = index == _panelIndex;
        final current = index == _state.player.currentLineIndex;
        return _panelRow(
          active: active,
          label: '线路 ${index + 1}',
          subtitle: current ? '当前' : null,
          onTap: () {
            setState(() => _panelIndex = index);
            _activatePanel();
          },
          trailing: current
              ? Icon(Icons.check_rounded, size: context.tvDp(18), color: TvTheme.focusColor)
              : null,
        );
      },
    );
  }

  Widget _buildDanmakuList(BuildContext context) {
    return Obx(() {
      final messages = _ctrl.danmakuMessages;
      final chat = messages.where((m) => m.type == LiveMessageType.chat).toList();
      if (chat.isEmpty) return TvEmpty(message: '暂无弹幕');
      return ListView.builder(
        controller: _panelScroll,
        itemCount: chat.length,
        itemBuilder: (context, index) {
          final m = chat[chat.length - 1 - index];
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: context.tvDp(6), vertical: context.tvDp(5)),
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: TextStyle(fontSize: context.tvSp(13), height: 1.4),
                children: [
                  TextSpan(text: '${m.userName}：', style: TextStyle(color: TvTheme.focusColor)),
                  TextSpan(text: m.message, style: TextStyle(color: TvTheme.textPrimary)),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

/// 底部控制栏条目
class _BarItem extends StatelessWidget {
  const _BarItem({required this.icon, required this.label, required this.active, this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: TvTheme.focusDuration,
        curve: TvTheme.focusCurve,
        padding: EdgeInsets.symmetric(horizontal: context.tvDp(14), vertical: context.tvDp(8)),
        decoration: BoxDecoration(
          color: active ? TvTheme.focusColor : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(context.tvDp(12)),
          border: Border.all(color: active ? Colors.white70 : Colors.transparent),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: context.tvDp(22), color: active ? Colors.white : Colors.white70),
            SizedBox(height: context.tvDp(3)),
            Text(label, style: TextStyle(fontSize: context.tvSp(12), color: Colors.white)),
          ],
        ),
      ),
    );
  }
}


/// TV 弹幕飘屏：顶部 1/3 区域三条车道滚动。
/// 消息源=LivePlayController.danmakuMessages（仅聊天类型）；
/// 受"显示弹幕"开关控制；速度与手机端弹幕速度设置共用。
class _TvDanmakuOverlay extends StatefulWidget {
  const _TvDanmakuOverlay();

  @override
  State<_TvDanmakuOverlay> createState() => _TvDanmakuOverlayState();
}

class _FlyingDanmaku {
  LiveMessage message = LiveMessage(
      type: LiveMessageType.chat, userName: '', message: '', color: LiveMessageColor.white);
  int lane = 0;
  double t = 0; // 0=右缘外 1=完全离开左缘
  double width = 0;
}

class _TvDanmakuOverlayState extends State<_TvDanmakuOverlay> {
  final List<_FlyingDanmaku> _flying = [];
  int _lastSeenCount = 0;
  int _lane = 0;
  Timer? _ticker;
  Worker? _msgWorker;
  static const int _laneCount = 3;
  static const Duration _tick = Duration(milliseconds: 33);

  LivePlayController get _ctrl => Get.find<LivePlayController>();

  @override
  void initState() {
    super.initState();
    _lastSeenCount = _ctrl.danmakuMessages.length;
    // 消息监听只注册一次（不能放 build 里，否则每次重建叠加 worker）
    _msgWorker = ever(_ctrl.danmakuMessages, (_) => _onMessages());
    _ticker = Timer.periodic(_tick, (_) => _tickStep());
  }

  void _tickStep() {
    if (!mounted || _flying.isEmpty) return;
    final speed = SettingsService.to.danmaku.danmakuSpeed.v.clamp(20, 400).toDouble() * 3;
    final w = MediaQuery.sizeOf(context).width;
    final dt = _tick.inMilliseconds / 1000.0;
    for (final item in _flying) {
      item.t += (speed * dt) / (w + item.width);
    }
    _flying.removeWhere((item) => item.t >= 1.0);
    if (mounted) setState(() {});
  }

  void _onMessages() {
    final messages = _ctrl.danmakuMessages;
    if (messages.length < _lastSeenCount) {
      _lastSeenCount = messages.length; // 历史被清（切房等），不补发
      return;
    }
    for (var i = _lastSeenCount; i < messages.length; i++) {
      final m = messages[i];
      if (m.type != LiveMessageType.chat) continue;
      if (m.message.isEmpty) continue;
      _flying.add(_FlyingDanmaku()
        ..message = m
        ..lane = _lane
        ..t = 0
        ..width = 0);
      _lane = (_lane + 1) % _laneCount;
    }
    _lastSeenCount = messages.length;
  }

  @override
  void dispose() {
    _msgWorker?.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final enabled = SettingsService.to.danmaku.enableDanmakuDisplay.v;
      if (!enabled) {
        if (_flying.isNotEmpty) _flying.clear();
        return const SizedBox.shrink();
      }
      final fontSize = context.tvSp(SettingsService.to.danmaku.danmakuFontSize.v);
      final opacity = SettingsService.to.danmaku.danmakuOpacity.v.clamp(0.1, 1.0);
      final w = MediaQuery.sizeOf(context).width;
      // 显示区域：占屏幕高度的比例（0.25~1.0），车道高度随之伸缩
      final area = SettingsService.to.danmaku.danmakuArea.v.clamp(0.25, 1.0);
      final overlayH = MediaQuery.sizeOf(context).height * 0.55 * area;
      final laneH = (overlayH / _laneCount).clamp(fontSize * 1.4, double.infinity);
      // 文本宽度用字数×字号估算（省去逐帧测量）
      double itemLeft(_FlyingDanmaku item) {
        final estWidth = (item.message.userName.length + item.message.message.length) * fontSize * 1.05;
        item.width = estWidth;
        return w - item.t * (w + estWidth);
      }

      return IgnorePointer(
        child: SizedBox(
          width: double.infinity,
          height: laneH * _laneCount + context.tvDp(16),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final item in _flying)
                Positioned(
                  left: itemLeft(item),
                  top: context.tvDp(16) + item.lane * laneH,
                  child: Text(
                    '${item.message.userName}：${item.message.message}',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: fontSize,
                      color: Colors.white.withValues(alpha: opacity),
                      shadows: const [
                        Shadow(blurRadius: 4, color: Colors.black, offset: Offset(1, 1)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
