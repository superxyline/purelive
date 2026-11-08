import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/tv_focus.dart';
import '../core/tv_theme.dart';

/// M1 焦点探针：验证电视遥控器的原始 KeyEvent 全部可达 Flutter。
/// 验收通过后把 [TvApp.kProbe] 改为 false 即直接进主界面。
class TvProbePage extends StatefulWidget {
  const TvProbePage({super.key, required this.onEnter});

  final VoidCallback onEnter;

  @override
  State<TvProbePage> createState() => _TvProbePageState();
}

class _TvProbePageState extends State<TvProbePage> {
  final List<String> _events = [];

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      setState(() {
        _events.insert(0, '${event.logicalKey.keyLabel} (${event.logicalKey.keyId.toRadixString(16)})');
        if (_events.length > 14) _events.removeLast();
      });
    }
    return KeyEventResult.ignored; // 探针页只记录不消费
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: EdgeInsets.all(context.tvDp(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'M1 焦点探针',
              style: TextStyle(fontSize: context.tvSp(26), fontWeight: FontWeight.w700, color: TvTheme.textPrimary),
            ),
            SizedBox(height: context.tvDp(8)),
            Text(
              '按遥控器的方向键/OK/返回/菜单，下方应实时显示键名；确认全部可达后选「进入主界面」。',
              style: TextStyle(fontSize: context.tvSp(15), color: TvTheme.textSecondary),
            ),
            SizedBox(height: context.tvDp(12)),
            Expanded(
              child: Focus(
                // 不 autofocus：让"进入主界面"按钮持有初始焦点；
                // 容器只负责记录"按钮未聚焦时"按下的键
                onKeyEvent: _onKey,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(context.tvDp(16)),
                  decoration: BoxDecoration(
                    color: TvTheme.card,
                    borderRadius: BorderRadius.circular(context.tvDp(TvTheme.panelRadius)),
                    border: Border.all(color: TvTheme.divider),
                  ),
                  child: _events.isEmpty
                      ? Text('（等待按键...）', style: TextStyle(fontSize: context.tvSp(14), color: TvTheme.textSecondary))
                      : Wrap(
                          spacing: context.tvDp(8),
                          runSpacing: context.tvDp(8),
                          children: _events
                              .map((e) => Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: context.tvDp(8), vertical: context.tvDp(2)),
                                    decoration: BoxDecoration(
                                      color: TvTheme.subtleFill,
                                      borderRadius: BorderRadius.circular(context.tvDp(6)),
                                    ),
                                    child: Text(e,
                                        style: TextStyle(fontSize: context.tvSp(13), color: TvTheme.textPrimary)),
                                  ))
                              .toList(),
                        ),
                ),
              ),
            ),
            SizedBox(height: context.tvDp(16)),
            Center(
              child: TvFocusable(
                autofocus: true,
                borderRadius: BorderRadius.circular(context.tvDp(999)),
                focusedBackgroundColor: TvTheme.focusColor,
                unfocusedBackgroundColor: TvTheme.subtleFill,
                onSelect: widget.onEnter,
                builder: (context, focused) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: context.tvDp(32), vertical: context.tvDp(12)),
                  child: Text(
                    '进入 TV 主界面',
                    style: TextStyle(
                        fontSize: context.tvSp(18), fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
