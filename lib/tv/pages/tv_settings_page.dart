import 'package:flutter/material.dart';
import 'tv_lan_sync_page.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/utils/player_consts.dart';

import '../core/tv_settings.dart';
import '../core/tv_theme.dart';

/// TV 设置页（可设置项对齐 pure_live_TV：播放器/弹幕/界面/账号/关于）。
/// 不照搬手机端的全部设置项——TV 只保留遥控可操作、有意义的子集。
/// 索引选择模型：↑↓ 移动，OK 切换/循环，Back 退回主页。
class TvSettingsPage extends StatefulWidget {
  const TvSettingsPage({super.key});

  @override
  State<TvSettingsPage> createState() => _TvSettingsPageState();
}

class _TvSettingsRow {
  final String? group; // 分组标题（非选择行）
  final String? label;
  final VoidCallback? onOk;
  final String Function()? valueText;

  const _TvSettingsRow({this.group, this.label, this.onOk, this.valueText});
}

class _TvSettingsPageState extends State<TvSettingsPage> {
  int _index = 0;
  late List<_TvSettingsRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = _buildRows();
    // 初始高亮跳到第一个可选行（index 0 是分组标题）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isSelectable(_index)) _move(1);
    });
  }

  List<_TvSettingsRow> _buildRows() {
    final dm = SettingsService.to.danmaku;
    final cookie = SettingsService.to.cookieManager;
    final player = SettingsService.to.player;
    final engineKeys = PlayerConsts.engines.keys.toList();

    String engineName(String key) => i18n(PlayerConsts.names[key] ?? key);

    return [
      const _TvSettingsRow(group: '播放器'),
      _TvSettingsRow(
        label: '播放内核（重启生效）',
        valueText: () => engineName(player.videoPlayerKey.v),
        onOk: () {
          final i = engineKeys.indexOf(player.videoPlayerKey.v);
          player.videoPlayerKey.v = engineKeys[(i + 1) % engineKeys.length];
        },
      ),
      _TvSettingsRow(
        label: '兼容模式（卡顿电视开启，重启生效）',
        valueText: () => player.playerCompatMode.v ? '开' : '关',
        onOk: () => player.playerCompatMode.v = !player.playerCompatMode.v,
      ),
      const _TvSettingsRow(group: '弹幕'),
      _TvSettingsRow(
        label: '显示弹幕',
        valueText: () => dm.enableDanmakuDisplay.v ? '开' : '关',
        onOk: () => dm.enableDanmakuDisplay.v = !dm.enableDanmakuDisplay.v,
      ),
      _TvSettingsRow(
        label: '弹幕字号',
        valueText: () => '${dm.danmakuFontSize.v.toStringAsFixed(0)}',
        onOk: () {
          const sizes = [14.0, 16.0, 18.0, 20.0, 22.0];
          final i = sizes.indexOf(dm.danmakuFontSize.v);
          dm.danmakuFontSize.v = sizes[(i + 1) % sizes.length];
        },
      ),
      _TvSettingsRow(
        label: '弹幕不透明度',
        valueText: () => '${(dm.danmakuOpacity.v * 100).toStringAsFixed(0)}%',
        onOk: () {
          const values = [0.4, 0.6, 0.8, 1.0];
          final i = values.indexOf(dm.danmakuOpacity.v);
          dm.danmakuOpacity.v = values[(i + 1) % values.length];
        },
      ),
      _TvSettingsRow(
        label: '弹幕速度',
        valueText: () {
          const names = ['很慢', '慢', '正常', '快', '很快'];
          const speeds = [40.0, 80.0, 120.0, 180.0, 240.0];
          final i = speeds.indexOf(dm.danmakuSpeed.v);
          return i >= 0 ? names[i] : '${dm.danmakuSpeed.v}';
        },
        onOk: () {
          const speeds = [40.0, 80.0, 120.0, 180.0, 240.0];
          final i = speeds.indexOf(dm.danmakuSpeed.v);
          dm.danmakuSpeed.v = speeds[(i + 1) % speeds.length];
        },
      ),
      _TvSettingsRow(
        label: '弹幕显示区域',
        valueText: () => '${(dm.danmakuArea.v * 100).toStringAsFixed(0)}%',
        onOk: () {
          const values = [0.25, 0.5, 0.75, 1.0];
          final i = values.indexOf(dm.danmakuArea.v);
          dm.danmakuArea.v = values[(i + 1) % values.length];
        },
      ),
      const _TvSettingsRow(group: '界面'),
      _TvSettingsRow(
        label: '卡片列数',
        valueText: () => '${TvSettings.gridColumns.v}',
        onOk: () {
          const cols = [4, 5, 6];
          final i = cols.indexOf(TvSettings.gridColumns.v);
          TvSettings.gridColumns.v = cols[(i + 1) % cols.length];
        },
      ),
      const _TvSettingsRow(group: '同步（扫码 / 局域网互推）'),
      _TvSettingsRow(
        label: '局域网设备互推（发现同网络设备，直接推送关注与登录态）',
        valueText: () => '',
        onOk: () {
          Navigator.of(Get.context!).push(MaterialPageRoute(builder: (_) => const TvLanSyncPage()));
        },
      ),
      const _TvSettingsRow(group: '账号登录态（手机扫码同步带入）'),
      _TvSettingsRow(
        label: '哔哩哔哩',
        valueText: () => cookie.bilibiliCookie.v.isNotEmpty ? '已登录' : '未同步',
      ),
      _TvSettingsRow(
        label: '斗鱼',
        valueText: () => cookie.douyuCookie.v.isNotEmpty ? '已登录' : '未同步',
      ),
      _TvSettingsRow(
        label: '虎牙',
        valueText: () => cookie.huyaCookie.v.isNotEmpty ? '已登录' : '未同步',
      ),
      _TvSettingsRow(
        label: '抖音',
        valueText: () => cookie.douyinCookie.v.isNotEmpty ? '已登录' : '未同步',
      ),
      _TvSettingsRow(
        label: '快手',
        valueText: () => cookie.kuaishouCookie.v.isNotEmpty ? '已登录' : '未同步',
      ),
      const _TvSettingsRow(group: '关于'),
      _TvSettingsRow(
        label: '关于 TV 模式',
        valueText: () => 'pure_live TV · M3',
      ),
    ];
  }

  bool _isSelectable(int i) => _rows[i].onOk != null;

  void _move(int delta) {
    var i = _index;
    for (var step = 0; step < _rows.length; step++) {
      i = (i + delta) % _rows.length;
      if (i < 0) i += _rows.length;
      if (_isSelectable(i)) {
        setState(() => _index = i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _rows = _buildRows(); // 设置值变化后刷新文案
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          _move(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _move(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.gameButtonA) {
          _rows[_index].onOk?.call();
          setState(() {});
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: EdgeInsets.all(context.tvDp(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置',
                  style: TextStyle(
                      fontSize: context.tvSp(26), fontWeight: FontWeight.w700, color: TvTheme.textPrimary)),
              SizedBox(height: context.tvDp(12)),
              Expanded(
                child: ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, i) {
                    final row = _rows[i];
                    if (row.group != null) {
                      return Padding(
                        padding: EdgeInsets.only(
                            top: context.tvDp(10), bottom: context.tvDp(6), left: context.tvDp(4)),
                        child: Text(row.group!,
                            style: TextStyle(
                                fontSize: context.tvSp(13),
                                fontWeight: FontWeight.w700,
                                color: TvTheme.focusColor)),
                      );
                    }
                    final selected = i == _index;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _index = i);
                        row.onOk?.call();
                      },
                      child: Container(
                        margin: EdgeInsets.only(bottom: context.tvDp(4)),
                        padding: EdgeInsets.symmetric(
                            horizontal: context.tvDp(14), vertical: context.tvDp(10)),
                        decoration: BoxDecoration(
                          color: selected ? TvTheme.focusColor : TvTheme.subtleFill,
                          borderRadius: BorderRadius.circular(context.tvDp(10)),
                          border: selected ? Border.all(color: Colors.white70) : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(row.label!,
                                  style: TextStyle(
                                      fontSize: context.tvSp(15),
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      color: selected ? Colors.white : TvTheme.textPrimary)),
                            ),
                            Text(row.valueText?.call() ?? '',
                                style: TextStyle(
                                    fontSize: context.tvSp(14),
                                    color: selected ? Colors.white : TvTheme.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Text('按返回键回到主界面',
                  style: TextStyle(fontSize: context.tvSp(12), color: TvTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
