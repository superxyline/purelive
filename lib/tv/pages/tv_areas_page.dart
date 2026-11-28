import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_category.dart';

import '../core/tv_theme.dart';
import '../core/tv_settings.dart';
import '../widgets/tv_room_card.dart';
import '../widgets/tv_widgets.dart';
import 'tv_play_page.dart';

/// TV 分类页：平台 Tab → 大分类网格 → 子分区网格 → 该分区房间（分页网格，页内下钻）。
/// 索引选择模型。
class TvAreasPage extends StatefulWidget {
  const TvAreasPage({super.key});

  @override
  State<TvAreasPage> createState() => _TvAreasPageState();
}

enum _TvMode { cat, sub, rooms }

class _TvAreasPageState extends State<TvAreasPage> {
  late final List<Site> _sites = Sites().availableSites();
  int _siteIndex = 0;
  _TvMode _mode = _TvMode.cat;
  int _catIndex = 0;
  int _subIndex = 0;
  int _cardIndex = 0;

  /// 顶部平台行是否持有焦点（cat 模式下从分类网格第一行按「上」进入）。
  /// 以前平台按钮只有 onTap（触摸/鼠标），遥控器完全点不到，是 TV 端的硬伤。
  bool _siteRowFocused = false;

  final Map<String, List<LiveCategory>> _catCache = {};
  final Map<String, List<LiveArea>> _subCache = {};
  final Map<String, List<LiveRoom>> _roomCache = {};
  final _loading = false.obs;

  String get _siteId => _sites[_siteIndex].id;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final id = _siteId;
    if (_catCache.containsKey(id)) return;
    _loading.value = true;
    try {
      final cats = await Sites.of(id).liveSite.getCategores(1, 1000).timeout(const Duration(seconds: 15));
      _catCache[id] = cats;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    } finally {
      _loading.value = false;
    }
  }

  List<LiveCategory> get _categories => _catCache[_siteId] ?? const [];

  List<LiveArea> get _subAreas {
    final cats = _categories;
    if (cats.isEmpty || _catIndex >= cats.length) return const [];
    final id = '${_siteId}:${cats[_catIndex].id}';
    return _subCache[id] ?? const [];
  }

  Future<void> _loadSubAreas() async {
    final cats = _categories;
    if (cats.isEmpty || _catIndex >= cats.length) return;
    final cacheId = '${_siteId}:${cats[_catIndex].id}';
    if (_subCache.containsKey(cacheId)) return;
    // 子分区通常已随大分类一起下发；没有才二次拉取
    final children = cats[_catIndex].children;
    if (children.isNotEmpty) {
      _subCache[cacheId] = children;
      if (mounted) setState(() {});
      return;
    }
    _loading.value = true;
    try {
      final cats2 = await Sites.of(_siteId).liveSite.getCategores(1, 1000).timeout(const Duration(seconds: 15));
      for (final c in cats2) {
        _subCache['$_siteId:${c.id}'] = c.children;
      }
    } catch (_) {}
    _loading.value = false;
    if (mounted) setState(() {});
  }

  Future<void> _loadRooms(LiveArea area) async {
    final cacheId = '$_siteId:${area.areaId}';
    if (_roomCache.containsKey(cacheId)) return;
    _loading.value = true;
    try {
      final rooms = await Sites.of(_siteId).liveSite.getCategoryRooms(area, page: 1).timeout(const Duration(seconds: 15));
      _roomCache[cacheId] = rooms;
    } catch (_) {
      _roomCache[cacheId] = const [];
    }
    _loading.value = false;
    if (mounted) setState(() {});
  }

  /// 分类 / 子分区网格的列数（与 build 里的 crossAxisCount 保持一致）
  static const int _areaGridColumns = 5;

  /// 在平台行内左右切换平台：切平台即回到分类层并重新加载分类
  void _switchSite(int d) {
    final next = (_siteIndex + d).clamp(0, _sites.length - 1);
    if (next == _siteIndex) return;
    setState(() {
      _siteIndex = next;
      _mode = _TvMode.cat;
      _catIndex = 0;
      _subIndex = 0;
      _cardIndex = 0;
    });
    _loadCategories();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final confirm = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
    final items = _currentItems();

    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      final d = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      // 平台行：↑ 即顶部边界（停住不动），↓ 回分类网格
      if (_siteRowFocused) {
        if (d > 0) setState(() => _siteRowFocused = false);
        return KeyEventResult.handled;
      }
      // 分类网格第一行按上 → 进入平台行（平台行只在分类层存在）
      if (_mode == _TvMode.cat && d < 0 && _catIndex < _areaGridColumns) {
        setState(() => _siteRowFocused = true);
        return KeyEventResult.handled;
      }
      if (_mode == _TvMode.cat && _catIndex + d < 0) return KeyEventResult.handled;
      if (_mode == _TvMode.sub && _subIndex + d < 0) return KeyEventResult.handled;
      setState(() {
        if (_mode == _TvMode.cat) {
          _catIndex = (_catIndex + d).clamp(0, (_categories.length - 1).clamp(0, 1 << 20));
        } else if (_mode == _TvMode.sub) {
          _subIndex = (_subIndex + d).clamp(0, (_subAreas.length - 1).clamp(0, 1 << 20));
        } else {
          _cardIndex = (_cardIndex + d).clamp(0, (items.length - 1).clamp(0, 1 << 20));
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final d = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
      if (_siteRowFocused) {
        _switchSite(d);
        return KeyEventResult.handled;
      }
      setState(() {
        if (_mode == _TvMode.cat) {
          _catIndex = (_catIndex + d).clamp(0, (_categories.length - 1).clamp(0, 1 << 20));
        } else if (_mode == _TvMode.sub) {
          _subIndex = (_subIndex + d).clamp(0, (_subAreas.length - 1).clamp(0, 1 << 20));
        } else {
          _cardIndex = (_cardIndex + d).clamp(0, (items.length - 1).clamp(0, 1 << 20));
        }
      });
      return KeyEventResult.handled;
    }
    if (confirm) {
      // 平台行 OK：收回焦点到分类网格（平台切换已由左右键即时生效）
      if (_siteRowFocused) {
        setState(() => _siteRowFocused = false);
        return KeyEventResult.handled;
      }
      _confirm(items);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      if (_siteRowFocused) {
        setState(() => _siteRowFocused = false);
        return KeyEventResult.handled;
      }
      if (_mode == _TvMode.rooms) {
        setState(() => _mode = _TvMode.sub);
        return KeyEventResult.handled;
      }
      if (_mode == _TvMode.sub) {
        setState(() => _mode = _TvMode.cat);
        return KeyEventResult.handled;
      }
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<dynamic> _currentItems() {
    switch (_mode) {
      case _TvMode.cat:
        return _categories;
      case _TvMode.sub:
        return _subAreas;
      case _TvMode.rooms:
        final subs = _subAreas;
        if (subs.isEmpty || _subIndex >= subs.length) return const [];
        return _roomCache['$_siteId:${subs[_subIndex].areaId}'] ?? const [];
    }
  }

  void _confirm(List<dynamic> items) {
    switch (_mode) {
      case _TvMode.cat:
        if (items.isEmpty || _catIndex >= items.length) return;
        _subIndex = 0;
        setState(() => _mode = _TvMode.sub);
        _loadSubAreas();
        break;
      case _TvMode.sub:
        final subs = _subAreas;
        if (subs.isEmpty || _subIndex >= subs.length) return;
        _cardIndex = 0;
        setState(() => _mode = _TvMode.rooms);
        _loadRooms(subs[_subIndex]);
        break;
      case _TvMode.rooms:
        if (items.isEmpty || _cardIndex >= items.length) return;
        final room = items[_cardIndex] as LiveRoom;
        try {
          tvEnsureLivePlayController(room);
        } catch (e) {
          debugPrint('[TvAreas] controller init failed: $e');
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TvPlayPage(room: room, rooms: List<LiveRoom>.from(items), initialIndex: _cardIndex),
        ));
        break;
    }
  }

  String get _title {
    switch (_mode) {
      case _TvMode.cat:
        return '分类';
      case _TvMode.sub:
        final cats = _categories;
        return cats.isEmpty ? '分类' : cats[_catIndex.clamp(0, cats.length - 1)].name;
      case _TvMode.rooms:
        final subs = _subAreas;
        if (subs.isEmpty || _subIndex >= subs.length) return '分区';
        return subs[_subIndex].areaName ?? '分区';
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _currentItems();
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: EdgeInsets.all(context.tvDp(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // 平台 Tab（cat 模式下可用遥控器 ↑ 进入本行，←→ 切换平台）
                  for (var i = 0; i < _sites.length; i++)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _siteRowFocused = false;
                          if (_mode != _TvMode.cat) _mode = _TvMode.cat;
                          _siteIndex = i;
                          _catIndex = 0;
                          _subIndex = 0;
                          _cardIndex = 0;
                        });
                        _loadCategories();
                      },
                      child: Builder(builder: (context) {
                        final selectedChip = i == _siteIndex;
                        final focusedChip = _siteRowFocused && selectedChip;
                        return Container(
                          margin: EdgeInsets.only(right: context.tvDp(8)),
                          padding: EdgeInsets.symmetric(
                              horizontal: context.tvDp(16), vertical: context.tvDp(6)),
                          decoration: BoxDecoration(
                            color: focusedChip
                                ? TvTheme.focusColor
                                : (selectedChip
                                    ? TvTheme.focusColor.withValues(alpha: 0.35)
                                    : TvTheme.subtleFill),
                            borderRadius: BorderRadius.circular(context.tvDp(999)),
                            border: selectedChip
                                ? Border.all(
                                    color: focusedChip ? Colors.white : TvTheme.focusColor,
                                    width: focusedChip ? 2 : 1)
                                : null,
                            boxShadow: focusedChip ? TvTheme.focusGlow : null,
                          ),
                          child: Text(_sites[i].name,
                              style: TextStyle(
                                  fontSize: context.tvSp(15),
                                  fontWeight: selectedChip || focusedChip
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: selectedChip || focusedChip
                                      ? Colors.white
                                      : TvTheme.textSecondary)),
                        );
                      }),
                    ),
                  SizedBox(width: context.tvDp(12)),
                  Text(_title,
                      style: TextStyle(
                          fontSize: context.tvSp(20), fontWeight: FontWeight.w700, color: TvTheme.textPrimary)),
                  if (_mode != _TvMode.cat) ...[
                    SizedBox(width: context.tvDp(8)),
                    Text('← 返回上级',
                        style: TextStyle(fontSize: context.tvSp(12), color: TvTheme.textSecondary)),
                  ],
                ],
              ),
              SizedBox(height: context.tvDp(12)),
              Expanded(
                child: Obx(() {
                  if (_loading.value && items.isEmpty) return TvLoading();
                  if (items.isEmpty) return TvEmpty(message: i18n('no_data'));
                  // 房间模式：真卡片网格
                  if (_mode == _TvMode.rooms) {
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: TvSettings.gridColumns.v,
                        childAspectRatio: TvTheme.gridChildAspectRatio,
                        crossAxisSpacing: context.tvDp(TvTheme.gridSpacing),
                        mainAxisSpacing: context.tvDp(TvTheme.gridSpacing),
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final room = items[index] as LiveRoom;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _cardIndex = index);
                            _confirm(items);
                          },
                          child: TvRoomCard(room: room, highlighted: index == _cardIndex),
                        );
                      },
                    );
                  }
                  // 分类/子分区：名称卡网格
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 2.6,
                      crossAxisSpacing: context.tvDp(10),
                      mainAxisSpacing: context.tvDp(10),
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      // 平台行持有焦点时，分类网格不再显示高亮（焦点在顶部平台行）
                      final active = index == (_mode == _TvMode.cat ? _catIndex : _subIndex) &&
                          !(_mode == _TvMode.cat && _siteRowFocused);
                      final name = _mode == _TvMode.cat
                          ? (items[index] as LiveCategory).name
                          : ((items[index] as LiveArea).areaName ?? '');
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_mode == _TvMode.cat) {
                              _catIndex = index;
                            } else {
                              _subIndex = index;
                            }
                          });
                          _confirm(items);
                        },
                        child: _CategoryCard(name: name, highlighted: active),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.name, required this.highlighted});

  final String name;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: TvTheme.focusDuration,
      curve: TvTheme.focusCurve,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlighted ? TvTheme.focusColor : TvTheme.card,
        borderRadius: BorderRadius.circular(context.tvDp(12)),
        border: Border.all(color: highlighted ? Colors.white70 : Colors.transparent, width: 2),
        boxShadow: highlighted ? TvTheme.focusGlow : null,
      ),
      child: Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: context.tvSp(14),
            fontWeight: FontWeight.w600,
            color: highlighted ? Colors.white : TvTheme.textPrimary),
      ),
    );
  }
}
