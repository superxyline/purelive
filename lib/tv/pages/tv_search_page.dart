import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';

import '../core/tv_theme.dart';
import '../widgets/tv_widgets.dart';
import 'tv_play_page.dart';

/// TV 搜索页：平台 Tab + 搜索框 + 结果网格。
/// 进入页面自动聚焦搜索框唤起系统 IME（等同手机点输入框）；
/// 键盘关闭后 OK 重新唤起键盘；搜索后 zone=grid 索引浏览结果。
class TvSearchPage extends StatefulWidget {
  const TvSearchPage({super.key});

  @override
  State<TvSearchPage> createState() => _TvSearchPageState();
}

enum _TvZone { input, tab, grid }

class _TvSearchPageState extends State<TvSearchPage> {
  late final List<Site> _sites = Sites().availableSites();
  int _siteIndex = 0;
  _TvZone _zone = _TvZone.input;

  final _keywordCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  final _gridController = ScrollController();
  final List<LiveRoom> _results = [];
  final _searching = false.obs;
  final _searched = false.obs;
  int _cardIndex = 0;

  @override
  void initState() {
    super.initState();
    // 进页面自动聚焦搜索框并唤起系统键盘（对齐手机点输入框的体验）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openKeyboard();
    });
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    _inputFocus.dispose();
    _gridController.dispose();
    super.dispose();
  }

  /// 聚焦搜索框并确保系统 IME 弹出。
  /// requestFocus 对已聚焦节点是幂等的，但 IME 可能已被系统收起，
  /// 因此再显式调一次 TextInput.show 兜底唤起键盘；部分电视 IME
  /// 连接建立较慢，500ms 后再补一次 show（仅当仍聚焦时）。
  void _openKeyboard() {
    _inputFocus.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.show');
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _inputFocus.hasFocus) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  Future<void> _doSearch() async {
    final keyword = _keywordCtrl.text.trim();
    if (keyword.isEmpty) return;
    _searching.value = true;
    _searched.value = true;
    try {
      final list = await Sites.of(_sites[_siteIndex].id)
          .liveSite
          .searchRooms(keyword)
          .timeout(const Duration(seconds: 15));
      _results.clear();
      _results.addAll(list);
      _cardIndex = 0;
    } catch (_) {
      _results.clear();
    } finally {
      _searching.value = false;
      if (mounted) {
        setState(() => _zone = _TvZone.grid);
        _inputFocus.unfocus();
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final goBack = key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape;
    final confirm = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;

    // 输入框聚焦中：OK = 确保键盘弹出（IME 可能被系统收起）；
    // 返回键取消聚焦（键盘打开时第一发 Back 已被系统用于收键盘）；
    // 其余按键全部交给输入框/IME。
    if (_inputFocus.hasFocus) {
      if (goBack) {
        _inputFocus.unfocus();
        setState(() => _zone = _TvZone.input);
        return KeyEventResult.handled;
      }
      if (confirm) {
        _openKeyboard();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_zone == _TvZone.tab) setState(() => _zone = _TvZone.input);
      if (_zone == _TvZone.grid) setState(() => _zone = _TvZone.tab);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_zone == _TvZone.input) setState(() => _zone = _TvZone.tab);
      if (_zone == _TvZone.tab) setState(() => _zone = _TvZone.grid);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final d = key == LogicalKeyboardKey.arrowRight ? 1 : -1;
      if (_zone == _TvZone.tab) {
        setState(() => _siteIndex = (_siteIndex + d).clamp(0, _sites.length - 1));
      } else if (_zone == _TvZone.grid && _results.isNotEmpty) {
        setState(() {
          _cardIndex = (_cardIndex + d).clamp(0, _results.length - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (confirm) {
      if (_zone == _TvZone.input) {
        _openKeyboard();
        return KeyEventResult.handled;
      }
      if (_zone == _TvZone.tab) {
        _doSearch();
        return KeyEventResult.handled;
      }
      if (_zone == _TvZone.grid && _results.isNotEmpty && _cardIndex < _results.length) {
        final room = _results[_cardIndex];
        try {
          tvEnsureLivePlayController(room);
        } catch (e) {
          debugPrint('[TvSearch] controller init failed: $e');
          return KeyEventResult.handled;
        }
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TvPlayPage(room: room, rooms: _results, initialIndex: _cardIndex),
        ));
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    if (goBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
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
              // 平台 Tab
              SizedBox(
                height: context.tvDp(52),
                child: Row(
                  children: [
                    for (var i = 0; i < _sites.length; i++)
                      GestureDetector(
                        onTap: () {
                          setState(() => _siteIndex = i);
                          if (_keywordCtrl.text.trim().isNotEmpty) _doSearch();
                        },
                        child: Container(
                          margin: EdgeInsets.only(right: context.tvDp(8)),
                          padding: EdgeInsets.symmetric(
                              horizontal: context.tvDp(18), vertical: context.tvDp(8)),
                          decoration: BoxDecoration(
                            color: i == _siteIndex
                                ? (_zone == _TvZone.tab ? TvTheme.focusColor : TvTheme.focusColor.withValues(alpha: 0.35))
                                : TvTheme.subtleFill,
                            borderRadius: BorderRadius.circular(context.tvDp(999)),
                          ),
                          child: Text(_sites[i].name,
                              style: TextStyle(
                                  fontSize: context.tvSp(16),
                                  fontWeight: FontWeight.w600,
                                  color: i == _siteIndex ? Colors.white : TvTheme.textSecondary)),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: context.tvDp(12)),
              // 搜索框
              TextField(
                controller: _keywordCtrl,
                focusNode: _inputFocus,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _doSearch(),
                style: TextStyle(fontSize: context.tvSp(16), color: TvTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '输入关键字搜索（OK 弹出键盘）',
                  hintStyle: TextStyle(fontSize: context.tvSp(14), color: TvTheme.textSecondary),
                  prefixIcon: Icon(Icons.search_rounded, size: context.tvDp(22), color: TvTheme.textSecondary),
                  isDense: true,
                  filled: true,
                  fillColor: TvTheme.subtleFill,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.tvDp(12))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.tvDp(12)),
                      borderSide: const BorderSide(color: TvTheme.focusColor, width: 2)),
                ),
              ),
              SizedBox(height: context.tvDp(12)),
              // 结果
              Expanded(
                child: Obx(() {
                  if (_searching.value) return TvLoading(message: '搜索中...');
                  if (_results.isEmpty) {
                    return TvEmpty(
                        icon: Icons.search_off_rounded,
                        message: _searched.value ? i18n('no_data') : '输入关键字后按搜索');
                  }
                  return GridView.builder(
                    controller: _gridController,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: TvTheme.gridColumns,
                      childAspectRatio: TvTheme.gridChildAspectRatio,
                      crossAxisSpacing: context.tvDp(TvTheme.gridSpacing),
                      mainAxisSpacing: context.tvDp(TvTheme.gridSpacing),
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final room = _results[index];
                      final highlighted = _zone == _TvZone.grid && index == _cardIndex;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _cardIndex = index);
                          try {
                            tvEnsureLivePlayController(room);
                          } catch (_) {
                            return;
                          }
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => TvPlayPage(room: room, rooms: _results, initialIndex: index),
                          ));
                        },
                        child: _SearchResultCard(room: room, highlighted: highlighted),
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

/// 搜索结果卡片（轻量版：头像+昵称+标题）
class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.room, required this.highlighted});

  final LiveRoom room;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final fg = highlighted ? Colors.black : TvTheme.textPrimary;
    final sub = highlighted ? Colors.black54 : TvTheme.textSecondary;
    return AnimatedContainer(
      duration: TvTheme.focusDuration,
      curve: TvTheme.focusCurve,
      decoration: BoxDecoration(
        color: highlighted ? TvTheme.focusedCard : TvTheme.card,
        borderRadius: BorderRadius.circular(context.tvDp(TvTheme.cardRadius)),
        border: Border.all(color: highlighted ? TvTheme.focusColor : Colors.transparent, width: 2),
        boxShadow: highlighted ? TvTheme.focusGlow : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.tvDp(TvTheme.cardRadius)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: TvTheme.subtleFill,
                    child: Icon(Icons.person_search_rounded,
                        size: context.tvDp(36), color: TvTheme.textSecondary),
                  ),
                  Positioned(
                    top: context.tvDp(8),
                    left: context.tvDp(8),
                    child: TvStatusChip(label: (room.platform ?? '').toUpperCase()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(context.tvDp(10), context.tvDp(6), context.tvDp(10), context.tvDp(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(room.nick?.isNotEmpty == true ? room.nick! : (room.roomId ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: context.tvSp(14), fontWeight: FontWeight.w700, color: fg, height: 1.2)),
                  if (room.title?.isNotEmpty == true)
                    Text(room.title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: context.tvSp(12), color: sub, height: 1.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
