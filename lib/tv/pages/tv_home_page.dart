import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/services/settings/favorite_room_controller.dart';

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

  /// 关注页顶部页签：已开播 / 未开播 / 全部。默认「已开播」，
  /// 与手机/平板关注页默认页签（tabOnlineIndex=0）保持一致。
  static const List<String> _favTabs = ['已开播', '未开播', '全部'];
  int _favTabIndex = 0;

  // ---- 热门（平台 Tab + 分页网格） ----
  late final List<Site> _sites = Sites().availableSites();
  int _siteIndex = 0;
  int _cardIndex = 0;
  DateTime _okDownAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastBackAt;

  // ---- 卡片长按菜单（置顶 / 移出关注）----
  // TV 上没有可靠的 Focus 遍历（见文件头注释），所以菜单同样用「索引模型」：
  // 由本页的单一 Focus 节点分派按键，高亮由 _cardMenuIndex 直接驱动。
  LiveRoom? _cardMenuRoom;
  bool _cardMenuOpen = false;
  int _cardMenuIndex = 0;
  final Map<String, List<LiveRoom>> _cache = {};
  final Map<String, int> _pageCache = {};
  final Map<String, bool> _endCache = {};
  bool _loading = false;
  final ScrollController _gridController = ScrollController();

  // ---- 关注 ----
  bool _favoriteRefreshed = false;
  bool _favoriteRefreshing = false;

  static const int _statusBatchSize = 12;
  static const Duration _detailTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _refreshFavoriteDetails();
    _loadPopularPage();
  }

  @override
  void dispose() {
    _gridController.dispose();
    super.dispose();
  }

  bool get _onPopular => _menuIndex == 1;

  /// 关注/热门是「内容型」菜单（右侧同一套网格），其余是独立页面。
  bool get _contentMenu => _menuIndex == 0 || _menuIndex == 1;

  List<LiveRoom> get _popularRooms => _cache[_sites[_siteIndex].id] ?? const <LiveRoom>[];

  /// 顶部页签当前选中项：热门页 = 平台索引，关注页 = 状态页签索引。
  int get _tabIndex => _onPopular ? _siteIndex : _favTabIndex;

  /// 当前网格的房间列表（关注页/热门页）
  List<LiveRoom> get _rooms => _onPopular ? _popularRooms : _sortedFavorite();

  // ---------------------------------------------------------------------------
  // 数据：关注页刷新（拉详情，与手机端 _refreshRoomDetails 同口径）
  // ---------------------------------------------------------------------------

  /// 关注页刷新：批量拉取直播间详情（light=true，跳过弹幕发现等进房才需要的
  /// 请求），更新标题 / 封面 / 热度 / 开播状态。
  ///
  /// 以前这里只调 getLiveStatus，卡片上的标题、热度、封面永远是旧值——这就是
  /// 「TV 刷新出来和手机刷出来的内容不一样」的直接原因。改为详情刷新后与手机端
  /// 完全同源；备注 / 标签是本地字段，平台详情不认识，替换前原样带回。
  Future<void> _refreshFavoriteDetails() async {
    if (_favoriteRefreshed) return;
    _favoriteRefreshed = true;
    final targets = SettingsService.to.fav.favoriteRooms.v
        .where((r) => (r.platform?.isNotEmpty ?? false) && r.roomId != null)
        .toList();
    if (targets.isEmpty) return;

    _favoriteRefreshing = true;
    final persistedRooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    var dirty = false;
    var lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    // 逐个房间回调 setState 会让大列表反复重排/重建：按 800ms 节流推给界面，
    // 收尾时强制 flush 一次保证最终数据落地。
    void flush({bool force = false}) {
      if (!dirty) return;
      if (!force && DateTime.now().difference(lastPush) < const Duration(milliseconds: 800)) return;
      dirty = false;
      lastPush = DateTime.now();
      SettingsService.to.fav.favoriteRooms.v = List<LiveRoom>.from(persistedRooms);
      if (mounted) setState(() {});
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= targets.length) return;
        final room = targets[i];
        final LiveRoom detail;
        try {
          detail = await Sites.of(room.platform!)
              .liveSite
              .getRoomDetail(roomId: room.roomId!, platform: room.platform!, light: true)
              .timeout(_detailTimeout);
        } catch (_) {
          // 单个房间失败（超时/风控）保留旧数据，不影响其它房间
          continue;
        }
        // 平台返回空对象（接口降级）时不落盘，避免把卡片清空
        if (!detail.hasUsableCardData) continue;
        final idx = persistedRooms.indexWhere(
          (e) => e.roomId == room.roomId && e.platform == room.platform,
        );
        if (idx == -1) continue;
        final previous = persistedRooms[idx];
        // 本地字段（备注 / 标签）平台不认识，刷新时原样保留
        detail.note = previous.note;
        detail.tagIds = List<String>.from(previous.tagIds);
        persistedRooms[idx] = detail;
        dirty = true;
        flush();
      }
    }

    try {
      await Future.wait(List.generate(_statusBatchSize, (_) => worker()));
    } finally {
      dirty = true;
      flush(force: true);
      _favoriteRefreshing = false;
    }
  }

  void _onSynced() {
    _favoriteRefreshed = false;
    _refreshFavoriteDetails();
  }

  /// 当前页签下的关注列表。过滤与排序口径对齐手机端：
  /// 页签（已开播 / 未开播 / 全部）→ 开播优先 → 开播即置顶 → 热度降序。
  List<LiveRoom> _sortedFavorite() {
    final app = SettingsService.to.app;
    final fav = SettingsService.to.fav;

    bool isLive(LiveRoom room) => room.liveStatus == LiveStatus.live && room.isRecord != true;

    final rooms = fav.favoriteRooms.v.where((room) {
      switch (_favTabIndex) {
        case 0:
          return isLive(room);
        case 1:
          return !isLive(room);
        default:
          return true;
      }
    }).toList();

    int sortValue(LiveRoom room) => room.audienceSortValue(
          preferRealOnline: app.preferRealOnlineCounts.v,
          platformEnabled: app.isRealOnlineEnabledFor(room.platform),
        );
    // 开播即置顶：置顶且开播才置顶，未开播的置顶房间按普通排序
    int pinned(LiveRoom room) => (isLive(room) && fav.isPinned(room)) ? 1 : 0;

    rooms.sort((a, b) {
      final la = isLive(a) ? 1 : 0;
      final lb = isLive(b) ? 1 : 0;
      if (la != lb) return lb.compareTo(la);
      final pa = pinned(a);
      final pb = pinned(b);
      if (pa != pb) return pb.compareTo(pa);
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

    // 卡片长按菜单打开时：所有按键由菜单消费（↑↓ 选择 / OK 执行 / 返回关闭）
    if (_cardMenuOpen) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _cardMenuIndex = (_cardMenuIndex + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, 1);
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.gameButtonA) {
        _runCardMenuAction();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
        setState(() => _cardMenuOpen = false);
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }

    // 遥控器菜单键：刷新当前页面数据（关注=重拉开播状态快通道；热门=强制刷新分页）
    final isMenuKey = key == LogicalKeyboardKey.contextMenu;
    if (isMenuKey) {
      if (_menuIndex == 0) {
        _favoriteRefreshed = false;
        _refreshFavoriteDetails();
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

    // 关注页网格：长按 OK（>500ms）= 切换「开播即置顶」（最多 3 个），短按进直播间
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
            _openCardMenu(room);
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

  /// 长按 OK：弹出卡片操作菜单（开播即置顶 / 移出关注）
  void _openCardMenu(LiveRoom room) {
    setState(() {
      _cardMenuRoom = room;
      _cardMenuIndex = 0;
      _cardMenuOpen = true;
    });
  }

  /// 执行当前高亮的菜单项：0 = 切换开播即置顶，1 = 移出关注
  void _runCardMenuAction() {
    final room = _cardMenuRoom;
    setState(() => _cardMenuOpen = false);
    if (room == null) return;

    if (_cardMenuIndex == 0) {
      _togglePin(room);
      return;
    }

    // 移出关注：菜单本身就是一次确认，不再二次弹窗
    SettingsService.to.fav.removeRoom(room);
    setState(() {
      _cardMenuRoom = null;
      _cardIndex = _cardIndex.clamp(0, (_rooms.length - 1).clamp(0, 1 << 20));
    });
    ToastUtil.show('已移出关注');
  }

  /// 长按 OK：切换「开播即置顶」（全局最多 3 个，超限提示先取消一个）。
  /// 置顶的直播间只要开播就恒排在关注列表最前面（见 _sortedFavorite 的 pinned 权重）。
  void _togglePin(LiveRoom room) {
    final fav = SettingsService.to.fav;
    final result = fav.togglePinned(room);
    if (result == null) {
      ToastUtil.show('最多置顶 ${FavoriteRoomController.maxPinnedRooms} 个直播间，请先取消一个');
      return;
    }
    setState(() {
      // 置顶会改变排序：把高亮跟随到该房间的新位置，避免焦点跳到别的直播间
      final idx = _rooms.indexWhere((r) => r.hasSameIdentity(room));
      if (idx >= 0) _cardIndex = idx;
    });
    if (result) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureCardVisible(_cardIndex, _rooms.length);
      });
      ToastUtil.show(
        '已置顶：开播后排最前（${fav.pinnedRooms.length}/${FavoriteRoomController.maxPinnedRooms}）',
      );
    } else {
      ToastUtil.show('已取消置顶');
    }
  }

  /// 侧栏上下切换菜单：切到热门时按需拉取（关注页用本地收藏，无需请求）
  void _switchMenu(int dy) {
    setState(() {
      _menuIndex = (_menuIndex + dy).clamp(0, _menus.length - 1);
      _cardIndex = 0;
    });
    if (_onPopular && _popularRooms.isEmpty) _loadPopularPage();
  }

  /// 顶部页签左右切换：热门 = 平台，关注 = 已开播 / 未开播 / 全部
  void _moveTab(int dx) {
    if (_onPopular) {
      final next = (_siteIndex + dx).clamp(0, _sites.length - 1);
      if (next != _siteIndex) _selectSite(next);
      return;
    }
    final next = (_favTabIndex + dx).clamp(0, _favTabs.length - 1);
    if (next == _favTabIndex) return;
    setState(() {
      _favTabIndex = next;
      _cardIndex = 0;
    });
    if (_gridController.hasClients) _gridController.jumpTo(0);
  }

  /// 打开侧栏「页面型」菜单（分类 / 搜索 / 同步关注 / 设置），返回后刷新网格
  void _openMenuPage(int index) {
    if (index < 2) return;
    final pages = <Widget>[
      TvAreasPage(),
      TvSearchPage(),
      TvSyncPage(onSynced: _onSynced),
      TvSettingsPage(),
    ];
    final pageIndex = index - 2;
    if (pageIndex < 0 || pageIndex >= pages.length) return;
    Navigator.of(Get.context!)
        .push(MaterialPageRoute(builder: (_) => pages[pageIndex]))
        .whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  KeyEventResult _move(int dy, int dx, List<LiveRoom> rooms) {
    switch (_zone) {
      case _TvZone.menu:
        if (dy != 0) {
          _switchMenu(dy);
          return KeyEventResult.handled;
        }
        if (dx > 0) {
          // 右键 = 进入内容区：内容型菜单先落到顶部页签行，页面型菜单直接打开页面
          if (_contentMenu) {
            setState(() => _zone = _TvZone.tab);
          } else {
            _openMenuPage(_menuIndex);
          }
        }
        return KeyEventResult.handled;

      case _TvZone.tab:
        if (dx != 0) {
          // 左边界再按左 = 回侧栏（页签行唯一的出口，避免「按上突然跳回菜单」）
          if (dx < 0 && _tabIndex == 0) {
            setState(() => _zone = _TvZone.menu);
            return KeyEventResult.handled;
          }
          _moveTab(dx);
          return KeyEventResult.handled;
        }
        if (dy > 0) {
          setState(() {
            _zone = _TvZone.grid;
            _cardIndex = rooms.isEmpty ? 0 : _cardIndex.clamp(0, rooms.length - 1);
          });
          if (rooms.isNotEmpty) _ensureCardVisible(_cardIndex, rooms.length);
          return KeyEventResult.handled;
        }
        // 页签行按上：停住不动——顶部就是边界，不再跳回左侧菜单
        return KeyEventResult.handled;

      case _TvZone.grid:
        if (rooms.isEmpty) {
          setState(() => _zone = _TvZone.tab);
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
            // 第一行向上 → 顶部页签行（而不是直接跳侧栏，保持层级：网格 → 页签 → 侧栏）
            setState(() => _zone = _TvZone.tab);
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
        // 页面型菜单（分类/搜索/同步/设置）：直接进入页面
        if (_menuIndex >= 2) {
          _openMenuPage(_menuIndex);
          return KeyEventResult.handled;
        }
        // 内容型菜单（关注/热门）：OK 只做「选中」——切换右侧内容，焦点留在侧栏。
        // 进内容区请按右键，符合电视端「导航栏只切换、方向键进内容」的常规习惯，
        // 也避免侧栏按一下 OK 就把焦点塞进卡片、再按一次就误开播。
        if (_onPopular && _popularRooms.isEmpty) _loadPopularPage();
        return KeyEventResult.handled;

      case _TvZone.tab:
        // OK = 进入内容网格（刷新统一走遥控器菜单键，避免「重复按当前平台」歧义）
        setState(() {
          _zone = _TvZone.grid;
          _cardIndex = rooms.isEmpty ? 0 : _cardIndex.clamp(0, rooms.length - 1);
        });
        if (rooms.isNotEmpty) _ensureCardVisible(_cardIndex, rooms.length);
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
            if (_cardMenuOpen && _cardMenuRoom != null) _buildCardMenu(context),
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
                    // 触摸/鼠标路径：页面型菜单直接进页面；内容型切到顶部页签行。
                    // （遥控器 OK 走 _confirm，行为是「只切换、焦点留在侧栏」）
                    if (index >= 2) {
                      setState(() => _menuIndex = index);
                      _openMenuPage(index);
                      return;
                    }
                    setState(() {
                      _menuIndex = index;
                      _zone = _TvZone.tab;
                      _cardIndex = 0;
                    });
                    if (index == 1 && _popularRooms.isEmpty) _loadPopularPage();
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
    // 关注页与热门页共用同一套「顶部页签行 + 网格」结构：
    // 热门是平台页签，关注是 已开播 / 未开播 / 全部 状态页签（默认已开播，对齐手机端）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTabBar(context),
        Expanded(child: _buildGrid(context, rooms)),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final tabFocused = _zone == _TvZone.tab;
    final labels = _onPopular ? _sites.map((s) => s.name).toList() : _favTabs;
    final selectedIndex = _tabIndex;
    return SizedBox(
      height: context.tvDp(56),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.tvDp(8)),
        itemCount: labels.length,
        separatorBuilder: (_, _) => SizedBox(width: context.tvDp(8)),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          final focused = tabFocused && index == selectedIndex;
          return GestureDetector(
            onTap: () {
              if (_onPopular) {
                _selectSite(index);
              } else {
                setState(() {
                  _favTabIndex = index;
                  _cardIndex = 0;
                });
                if (_gridController.hasClients) _gridController.jumpTo(0);
              }
            },
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
                labels[index],
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

  String get _emptyMessage {
    if (_onPopular) return i18n('no_data');
    switch (_favTabIndex) {
      case 0:
        return '暂无已开播的直播间\n按 ← / → 可切换到「未开播」或「全部」';
      case 1:
        return '暂无未开播的直播间\n按 ← / → 可切换到「已开播」或「全部」';
      default:
        return '暂无关注的直播间\n可到「同步关注」导入，或去「热门」关注主播';
    }
  }

  Widget _buildGrid(BuildContext context, List<LiveRoom> rooms) {
    if (rooms.isEmpty) {
      return _loading
          ? TvLoading()
          : TvEmpty(
              icon: _onPopular ? Icons.live_tv_rounded : Icons.favorite_border_rounded,
              message: _emptyMessage,
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

  /// 卡片长按菜单：半透明遮罩 + 居中操作卡（索引高亮，遥控器 ↑↓/OK/返回）
  Widget _buildCardMenu(BuildContext context) {
    final room = _cardMenuRoom!;
    final fav = SettingsService.to.fav;
    final pinned = fav.isPinned(room);
    final name = (room.note?.trim().isNotEmpty ?? false)
        ? room.note!.trim()
        : ((room.nick?.isNotEmpty ?? false)
            ? room.nick!
            : ((room.title?.isNotEmpty ?? false) ? room.title! : (room.roomId ?? '')));

    final entries = <(IconData, String, String)>[
      (
        pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        pinned ? '取消置顶' : '开播即置顶',
        pinned
            ? '取消后不再排最前'
            : '该直播间开播后恒排关注列表最前（最多 ${FavoriteRoomController.maxPinnedRooms} 个）',
      ),
      (Icons.heart_broken_rounded, '移出关注', '从关注列表中移除该直播间'),
    ];

    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _cardMenuOpen = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.62),
          alignment: Alignment.center,
          child: GestureDetector(
            // 吞掉卡片区域的点击，避免误关
            onTap: () {},
            child: Container(
              width: context.tvDp(470),
              padding: EdgeInsets.symmetric(
                  horizontal: context.tvDp(16), vertical: context.tvDp(16)),
              decoration: BoxDecoration(
                color: TvTheme.card,
                borderRadius: BorderRadius.circular(context.tvDp(18)),
                border: Border.all(color: TvTheme.divider),
                boxShadow: TvTheme.focusGlow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.tvSp(18),
                      fontWeight: FontWeight.w700,
                      color: TvTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: context.tvDp(4)),
                  Text(
                    '↑↓ 选择 · OK 确定 · 返回关闭',
                    style: TextStyle(fontSize: context.tvSp(12), color: TvTheme.textSecondary),
                  ),
                  SizedBox(height: context.tvDp(10)),
                  for (var i = 0; i < entries.length; i++)
                    _buildCardMenuRow(context, i, entries[i]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardMenuRow(BuildContext context, int index, (IconData, String, String) entry) {
    final focused = index == _cardMenuIndex;
    final fg = focused ? Colors.black : TvTheme.textPrimary;
    final sub = focused ? Colors.black54 : TvTheme.textSecondary;
    return Container(
      margin: EdgeInsets.only(top: context.tvDp(8)),
      padding: EdgeInsets.symmetric(
          horizontal: context.tvDp(14), vertical: context.tvDp(10)),
      decoration: BoxDecoration(
        color: focused ? TvTheme.focusColor : TvTheme.subtleFill,
        borderRadius: BorderRadius.circular(context.tvDp(12)),
      ),
      child: Row(
        children: [
          Icon(entry.$1, size: context.tvDp(22), color: fg),
          SizedBox(width: context.tvDp(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.$2,
                  style: TextStyle(
                    fontSize: context.tvSp(16),
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                SizedBox(height: context.tvDp(2)),
                Text(
                  entry.$3,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: context.tvSp(12), color: sub),
                ),
              ],
            ),
          ),
        ],
      ),
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

