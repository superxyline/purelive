import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';

import '../core/tv_theme.dart';
import '../widgets/tv_widgets.dart';
import '../widgets/tv_room_card.dart';
import 'tv_room_loading_page.dart';

import 'tv_areas_page.dart';
import 'tv_play_page.dart';
import 'tv_room_loading_page.dart';
import 'tv_search_page.dart';
import '../core/tv_settings.dart';
import 'tv_settings_page.dart';
import 'tv_sync_page.dart';

/// TV 壳（索引选择模型版）：
///
/// 不依赖 Flutter 焦点遍历（实测电视上会静默丢焦/autofocus 竞态），
/// 单一 [Focus] 节点接收全部按键，按 zone（侧栏/Tab条/网格）+ 索引分派，
/// 与 pure_live_TV 的"索引选择面板"同一设计思想。
/// 高亮由 highlighted 索引直接驱动，确定性 100%。
class TvHomePage extends StatefulWidget {
  const TvHomePage({super.key});

  @override
  State<TvHomePage> createState() => _TvHomePageState();
}

enum _TvZone { menu, tab, grid }

class _TvHomePageState extends State<TvHomePage> {
  // ---- 侧栏 ----
  static const List<(IconData, String)> _menus = [
    (Icons.favorite_rounded, '关注'),
    (Icons.local_fire_department_rounded, '热门'),
    (Icons.grid_view_rounded, '分类'),
    (Icons.search_rounded, '搜索'),
    (Icons.qr_code_scanner_rounded, '同步关注'),
    (Icons.settings_rounded, '设置'),
  ];
  int _menuIndex = 0;
  _TvZone _zone = _TvZone.menu;

  // ---- 热门（平台 Tab + 分页网格） ----
  late final List<Site> _sites = Sites().availableSites();
  int _siteIndex = 0;
  int _cardIndex = 0;
  DateTime _okDownAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastBackAt;
  final Map<String, List<LiveRoom>> _cache = {};
  final Map<String, int> _pageCache = {};
  final Map<String, bool> _endCache = {};
  bool _loading = false;
  final ScrollController _gridController = ScrollController();

  // ---- 关注 ----
  bool _favoriteRefreshed = false;
  bool _favoriteRefreshing = false;

  static const int _statusBatchSize = 12;
  static const Duration _statusTimeout = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _refreshFavoriteStatus();
    _loadPopularPage();
  }

  @override
  void dispose() {
    _gridController.dispose();
    super.dispose();
  }

  bool get _onPopular => _menuIndex == 1;
  List<LiveRoom> get _popularRooms => _cache[_sites[_siteIndex].id] ?? const <LiveRoom>[];

  /// 当前网格的房间列表（关注页/热门页）
  List<LiveRoom> get _rooms => _onPopular ? _popularRooms : _sortedFavorite();

  // ---------------------------------------------------------------------------
  // 数据：关注开播状态刷新（已开播在前+热度降序）
  // ---------------------------------------------------------------------------

  Future<void> _refreshFavoriteStatus() async {
    if (_favoriteRefreshed) return;
    _favoriteRefreshed = true;
    final rooms = SettingsService.to.fav.favoriteRooms.v
        .where((r) => (r.platform?.isNotEmpty ?? false) && r.roomId != null)
        .toList();
    if (rooms.isEmpty) return;

    _favoriteRefreshing = true;
    final persistedRooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    var dirty = false;
    void flush() {
      if (!dirty) return;
      dirty = false;
      SettingsService.to.fav.favoriteRooms.v = List<LiveRoom>.from(persistedRooms);
      if (mounted) setState(() {});
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= rooms.length) return;
        final room = rooms[i];
        final bool isLive;
        try {
          isLive = await Sites.of(room.platform!)
              .liveSite
              .getLiveStatus(platform: room.platform!, roomId: room.roomId!)
              .timeout(_statusTimeout);
        } catch (_) {
          continue;
        }
        final idx = persistedRooms.indexWhere(
          (e) => e.roomId == room.roomId && e.platform == room.platform,
        );
        if (idx == -1) continue;
        final target = persistedRooms[idx];
        final nextStatus = isLive ? LiveStatus.live : LiveStatus.offline;
        if (target.liveStatus == nextStatus) continue;
        target.liveStatus = nextStatus;
        target.status = isLive;
        dirty = true;
        flush();
      }
    }

    try {
      await Future.wait(List.generate(_statusBatchSize, (_) => worker()));
    } finally {
      dirty = true;
      flush();
      _favoriteRefreshing = false;
    }
  }

  void _onSynced() {
    _favoriteRefreshed = false;
    _refreshFavoriteStatus();
  }

  List<LiveRoom> _sortedFavorite() {
    final app = SettingsService.to.app;
    final rooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    int sortValue(LiveRoom room) => room.audienceSortValue(
          preferRealOnline: app.preferRealOnlineCounts.v,
          platformEnabled: app.isRealOnlineEnabledFor(room.platform),
        );
    rooms.sort((a, b) {
      final la = a.liveStatus == LiveStatus.live && a.status == true ? 1 : 0;
      final lb = b.liveStatus == LiveStatus.live && b.status == true ? 1 : 0;
      if (la != lb) return lb.compareTo(la);
      return sortValue(b).compareTo(sortValue(a));
    });
    return rooms;
  }

  // ---------------------------------------------------------------------------
  // 数据：热门分页
  // ---------------------------------------------------------------------------

  Future<void> _loadPopularPage({bool refresh = false}) async {
    if (_loading) return;
    final id = _sites[_siteIndex].id;
    if (_endCache[id] == true && !refresh) return;
    final page = refresh ? 1 : ((_pageCache[id] ?? 0) + 1);
    _loading = true;
    if (mounted) setState(() {});
    try {
      final list = await Sites.of(id).liveSite.getRecommendRooms(page: page).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (refresh) {
        _cache[id] = list;
        _cardIndex = 0;
      } else {
        final rooms = List<LiveRoom>.from(_cache[id] ?? const <LiveRoom>[]);
        rooms.addAll(list);
        _cache[id] = rooms;
      }
      _pageCache[id] = page;
      if (list.isEmpty) _endCache[id] = true;
      setState(() {});
      // 内容不足一屏时无法滚动触发加载，主动续载
      if (_endCache[id] != true && (_cache[id]?.length ?? 0) < TvTheme.gridColumns * 3) {
        _loadPopularPage();
      }
    } catch (_) {
      // 单页失败不致命：已有缓存则继续展示
    } finally {
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  void _selectSite(int index) {
    final same = index == _siteIndex;
    setState(() => _siteIndex = index);
    final id = _sites[_siteIndex].id;
    if (same) {
      // 重复按当前平台 = 刷新
      _cache.remove(id);
      _pageCache.remove(id);
      _endCache.remove(id);
      _cardIndex = 0;
      _loadPopularPage(refresh: true);
      return;
    }
    _cardIndex = 0;
    _loadPopularPage();
  }

  // ---------------------------------------------------------------------------
  // 按键路由（单一入口，确定性分派）
  // ---------------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    try {
      return _onKeyInner(node, event);
    } catch (e) {
      debugPrint('[TvHome] key handler error: $e');
      return KeyEventResult.handled;
    }
  }

  KeyEventResult _onKeyInner(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    // 遥控器菜单键：刷新当前页面数据（关注=重拉开播状态快通道；热门=强制刷新分页）
    final isMenuKey = key == LogicalKeyboardKey.contextMenu;
    if (isMenuKey) {
      if (_menuIndex == 0) {
        _favoriteRefreshed = false;
        _refreshFavoriteStatus();
        ToastUtil.show(i18n('tv_refresh_done'));
      } else if (_menuIndex == 1) {
        _loadPopularPage(refresh: true);
        ToastUtil.show(i18n('tv_refresh_done'));
      }
      return KeyEventResult.handled;
    }
    final confirm = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
    final rooms = _rooms;

    // 关注页网格：长按 OK（>500ms）移出关注，短按进直播间
    if (confirm) {
      if (event is KeyDownEvent) {
        _okDownAt = DateTime.now();
        return KeyEventResult.handled;
      }
      if (event is KeyUpEvent) {
        final long = DateTime.now().difference(_okDownAt) > const Duration(milliseconds: 500);
        if (_zone == _TvZone.grid && !_onPopular && _cardIndex < rooms.length) {
          final room = rooms[_cardIndex];
          if (long) {
            SettingsService.to.fav.removeRoom(room);
            setState(() {
              if (_cardIndex >= _rooms.length) _cardIndex = (_rooms.length - 1).clamp(0, 1 << 20);
            });
            return KeyEventResult.handled;
          }
        }
        _confirm(rooms);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.arrowUp) return _move(-1, 0, rooms);
    if (key == LogicalKeyboardKey.arrowDown) return _move(1, 0, rooms);
    if (key == LogicalKeyboardKey.arrowLeft) return _move(0, -1, rooms);
    if (key == LogicalKeyboardKey.arrowRight) return _move(0, 1, rooms);
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      // 主页返回 = 退出应用：2 秒内连按两次才退出到桌面（防误退）。
      // 双击判定在 _handleExitBack——PopScope 焦点兜底路径共用同一时间戳。
      _handleExitBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 退出应用的连按判定：2 秒内第二次返回键才真正退出，否则提示。
  /// 两条路径共用（①Focus.onKeyEvent 命中时；②Router popRoute→maybePop→
  /// PopScope 兜底）。同一次物理按压会先后走这两条路径，300ms 内的重复
  /// 调用视为同一次按压直接吞掉——否则单按返回就触发"第二次"直接退出
  /// （实测现象：单击退出+toast 闪现）。
  bool _handleExitBack() {
    final now = DateTime.now();
    if (_lastBackAt != null) {
      final delta = now.difference(_lastBackAt!);
      if (delta < const Duration(milliseconds: 150)) return false;
      if (delta <= const Duration(seconds: 2)) {
        SystemNavigator.pop();
        return true;
      }
    }
    _lastBackAt = now;
    ToastUtil.show(i18n('exit_app_confirm'));
    return false;
  }

  KeyEventResult _move(int dy, int dx, List<LiveRoom> rooms) {
    switch (_zone) {
      case _TvZone.menu:
        if (dy != 0) {
          setState(() {
            _menuIndex = (_menuIndex + dy).clamp(0, _menus.length - 1);
          });
        }
        if (dx > 0 && rooms.isNotEmpty) setState(() => _zone = _TvZone.grid);
        return KeyEventResult.handled;

      case _TvZone.tab:
        if (dx != 0) {
          setState(() {
            _siteIndex = (_siteIndex + dx).clamp(0, _sites.length - 1);
          });
        }
        if (dy > 0) setState(() => _zone = _TvZone.grid);
        if (dy < 0) setState(() => _zone = _TvZone.menu);
        return KeyEventResult.handled;

      case _TvZone.grid:
        if (rooms.isEmpty) {
          setState(() => _zone = _TvZone.menu);
          return KeyEventResult.handled;
        }
        final cols = TvSettings.gridColumns.v;
        final col = _cardIndex % cols;
        final row = _cardIndex ~/ cols;
        if (dx != 0) {
          // 最左列按左 → 侧边栏（任何行），不回绕到上一行
          if (dx < 0 && col == 0) {
            setState(() => _zone = _TvZone.menu);
            return KeyEventResult.handled;
          }
          final ni = (_cardIndex + dx).clamp(0, rooms.length - 1);
          setState(() => _cardIndex = ni);
          if (_onPopular && ni >= rooms.length - cols) _loadPopularPage();
          _ensureCardVisible(ni, rooms.length);
          return KeyEventResult.handled;
        }
        if (dy != 0) {
          final newRow = row + dy;
          if (newRow < 0) {
            // 第一行向上 → 侧边栏
            setState(() => _zone = _TvZone.menu);
            return KeyEventResult.handled;
          }
          var ni = newRow * cols + col;
          if (ni >= rooms.length) {
            final lastRow = (rooms.length - 1) ~/ cols;
            if (row >= lastRow) return KeyEventResult.handled;
            ni = rooms.length - 1;
          }
          setState(() => _cardIndex = ni);
          if (_onPopular && ni >= rooms.length - cols) _loadPopularPage();
          _ensureCardVisible(ni, rooms.length);
          return KeyEventResult.handled;
        }
        return KeyEventResult.handled;
    }
  }

  KeyEventResult _confirm(List<LiveRoom> rooms) {
    switch (_zone) {
      case _TvZone.menu:
        // 分类/搜索/同步/设置：推独立页面（返回后刷新网格）
        if (_menuIndex >= 2) {
          final pages = <Widget>[
            TvAreasPage(),
            TvSearchPage(),
            TvSyncPage(onSynced: _onSynced),
            TvSettingsPage(),
          ];
          Navigator.of(Get.context!)
              .push(MaterialPageRoute(builder: (_) => pages[_menuIndex - 2]))
              .whenComplete(() {
            if (mounted) setState(() {});
          });
          return KeyEventResult.handled;
        }
        // 关注/热门：切页并进入内容区
        setState(() => _zone = _TvZone.grid);
        _cardIndex = 0;
        if (_onPopular) _loadPopularPage();
        _ensureCardVisible(0, rooms.length);
        return KeyEventResult.handled;

      case _TvZone.tab:
        _selectSite(_siteIndex);
        return KeyEventResult.handled;

      case _TvZone.grid:
        if (rooms.isEmpty || _cardIndex >= rooms.length) return KeyEventResult.handled;
        final room = rooms[_cardIndex];
        _openRoom(room);
        return KeyEventResult.handled;
    }
  }

  void _ensureCardVisible(int index, int total) {
    if (!_gridController.hasClients) return;
    final viewport = _gridController.position.viewportDimension;
    final max = _gridController.position.maxScrollExtent;
    final gridWidth = _gridWidth();
    if (gridWidth <= 0) return;
    final cardH = gridWidth / TvTheme.gridColumns / TvTheme.gridChildAspectRatio;
    final row = index ~/ TvTheme.gridColumns;
    final top = row * (cardH + TvTheme.gridSpacing);
    final bottom = top + cardH;
    final current = _gridController.offset;
    if (top < current) {
      _gridController.animateTo(top.clamp(0.0, max), duration: TvTheme.pageTransitionDuration, curve: TvTheme.focusCurve);
    } else if (bottom > current + viewport) {
      _gridController.animateTo((bottom - viewport).clamp(0.0, max), duration: TvTheme.pageTransitionDuration, curve: TvTheme.focusCurve);
    }
  }

  double _gridWidth() {
    final size = MediaQuery.sizeOf(context);
    // 侧栏宽 228dp*scale + 内容 padding 16dp*scale；tvDp 因子同壳
    final scale = tvGeoScale(context);
    return (size.width - 228 * scale - 32 * scale - 24 * scale);
  }

  void _openRoom(LiveRoom room) {
    // M2：推送 TV 播放页（全屏视频 + TV 键位 + 面板）。
    // 不走 Get.toNamed —— TV 树下 Get.key 导航器未接上（实测静默无效）。
    try {
      tvEnsureLivePlayController(room);
    } catch (e) {
      debugPrint('[TvHome] controller init failed: $e');
      TvRoomLoadingPage.pendingRoom = room;
      Navigator.of(Get.context!).push(
        MaterialPageRoute(builder: (_) => const TvRoomLoadingPage()),
      );
      return;
    }
    final initialIndex = _rooms.indexWhere((r) => r.hasSameIdentity(room));
    Navigator.of(Get.context!).push(
      MaterialPageRoute(
        builder: (_) => TvPlayPage(
          room: room,
          rooms: _rooms,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
        ),
      ),
    ).then((_) {
      // 播放页内可能已换台：按最终房间同步网格高亮
      final last = TvPlayPage.lastRoom;
      if (last == null || !mounted) return;
      final i = _rooms.indexWhere((r) => r.hasSameIdentity(last));
      if (i >= 0 && i != _cardIndex) {
        _cardIndex = i;
        setState(() {});
      }
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    // 根路由 PopScope 兜底：返回主页后 Focus 可能失焦，BACK 直达 Navigator
    // 弹根路由导致单按退桌面。canPop:false 拦下所有弹根路由的尝试，统一走
    // _handleExitBack 的 2 秒连按判定（与 Focus 路径共用 _lastBackAt）。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _handleExitBack();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSideNav(context),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(context.tvDp(8)),
                    child: _buildContent(context, rooms),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildSideNav(BuildContext context) {
    return AnimatedContainer(
      duration: TvTheme.navExpandDuration,
      width: context.tvDp(228),
      padding: EdgeInsets.symmetric(vertical: context.tvDp(16)),
      decoration: BoxDecoration(
        color: TvTheme.background.withValues(alpha: 0.62),
        border: Border(right: BorderSide(color: TvTheme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.tvDp(16)),
            child: const _DigitalClock(),
          ),
          SizedBox(height: context.tvDp(20)),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: context.tvDp(12)),
              itemCount: _menus.length,
              itemBuilder: (context, index) {
                final (icon, title) = _menus[index];
                final focused = _zone == _TvZone.menu && index == _menuIndex;
                final selected = index == _menuIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _menuIndex = index;
                      _zone = _TvZone.grid;
                    });
                  },
                  child: Container(
                    margin: EdgeInsets.only(bottom: context.tvDp(6)),
                    padding: EdgeInsets.symmetric(
                        horizontal: context.tvDp(12), vertical: context.tvDp(14)),
                    decoration: BoxDecoration(
                      color: focused
                          ? TvTheme.focusColor
                          : (selected ? TvTheme.focusColor.withValues(alpha: 0.30) : Colors.transparent),
                      borderRadius: BorderRadius.circular(context.tvDp(14)),
                      boxShadow: focused ? TvTheme.focusGlow : null,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: context.tvDp(24), color: Colors.white),
                        SizedBox(width: context.tvDp(12)),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: context.tvSp(18),
                              fontWeight: focused || selected ? FontWeight.w700 : FontWeight.w500,
                              color: TvTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<LiveRoom> rooms) {
    if (_onPopular) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabBar(context),
          Expanded(child: _buildGrid(context, rooms)),
        ],
      );
    }
    return _buildGrid(context, rooms, withTopPadding: true);
  }

  Widget _buildTabBar(BuildContext context) {
    final tabFocused = _zone == _TvZone.tab;
    return SizedBox(
      height: context.tvDp(56),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.tvDp(8)),
        itemCount: _sites.length,
        separatorBuilder: (_, _) => SizedBox(width: context.tvDp(8)),
        itemBuilder: (context, index) {
          final selected = index == _siteIndex;
          final focused = tabFocused && index == _siteIndex;
          return GestureDetector(
            onTap: () => _selectSite(index),
            child: AnimatedContainer(
              duration: TvTheme.focusDuration,
              padding: EdgeInsets.symmetric(horizontal: context.tvDp(20), vertical: context.tvDp(8)),
              decoration: BoxDecoration(
                color: focused
                    ? TvTheme.focusColor
                    : (selected ? TvTheme.focusColor.withValues(alpha: 0.35) : TvTheme.subtleFill),
                borderRadius: BorderRadius.circular(context.tvDp(999)),
                boxShadow: focused ? TvTheme.focusGlow : null,
              ),
              child: Text(
                _sites[index].name,
                style: TextStyle(
                  fontSize: context.tvSp(17),
                  fontWeight: selected || focused ? FontWeight.w700 : FontWeight.w500,
                  color: focused ? Colors.white : (selected ? Colors.white : TvTheme.textSecondary),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid(BuildContext context, List<LiveRoom> rooms, {bool withTopPadding = false}) {
    if (rooms.isEmpty) {
      return _loading
          ? TvLoading()
          : TvEmpty(
              icon: _onPopular ? Icons.live_tv_rounded : Icons.favorite_border_rounded,
              message: _onPopular ? i18n('no_data') : '暂无关注的直播间',
            );
    }
    final clampedIndex = _cardIndex.clamp(0, rooms.length - 1);
    return GridView.builder(
      controller: _gridController,
      padding: EdgeInsets.all(context.tvDp(12)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: TvSettings.gridColumns.v,
        childAspectRatio: TvTheme.gridChildAspectRatio,
        crossAxisSpacing: context.tvDp(TvTheme.gridSpacing),
        mainAxisSpacing: context.tvDp(TvTheme.gridSpacing),
      ),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        final highlighted = _zone == _TvZone.grid && index == clampedIndex;
        return GestureDetector(
          onTap: () => _openRoom(room),
          child: TvRoomCard(
            room: room,
            highlighted: highlighted,
          ),
        );
      },
    );
  }
}

/// 数字时钟（每秒刷新）
class _DigitalClock extends StatefulWidget {
  const _DigitalClock();

  @override
  State<_DigitalClock> createState() => _DigitalClockState();
}

class _DigitalClockState extends State<_DigitalClock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}',
            maxLines: 1,
            style: TextStyle(
              fontSize: context.tvSp(26),
              fontWeight: FontWeight.w700,
              color: TvTheme.textPrimary,
            ),
          ),
        ),
        SizedBox(height: context.tvDp(2)),
        Text(
          '${_now.year}-${_two(_now.month)}-${_two(_now.day)}',
          maxLines: 1,
          style: TextStyle(fontSize: context.tvSp(13), color: TvTheme.textSecondary),
        ),
      ],
    );
  }
}

