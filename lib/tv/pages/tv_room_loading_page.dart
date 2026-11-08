import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';

import '../core/tv_theme.dart';

/// M1 过渡页：TV 侧点击卡片的落点，验证"网格 → OK → 详情页 → 返回"闭环。
/// M2 将替换为真正的 TvPlayPage（TV 播放页 + 遥控键位）。
class TvRoomLoadingPage extends StatefulWidget {
  const TvRoomLoadingPage({super.key});

  /// 推页前由调用方设置（MaterialPageRoute 无 arguments 通道）
  static LiveRoom? pendingRoom;

  @override
  State<TvRoomLoadingPage> createState() => _TvRoomLoadingPageState();
}

class _TvRoomLoadingPageState extends State<TvRoomLoadingPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final room = TvRoomLoadingPage.pendingRoom;
    final nick = room?.nick?.isNotEmpty == true ? room!.nick! : (room?.roomId ?? '');
    final platform = (room?.platform ?? '').toUpperCase();
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.goBack)) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (nick.isNotEmpty) ...[
                Text(
                  nick,
                  style: TextStyle(
                    fontSize: context.tvSp(22),
                    fontWeight: FontWeight.w700,
                    color: TvTheme.textPrimary,
                  ),
                ),
                SizedBox(height: context.tvDp(6)),
                Text(
                  '$platform · 直播间详情页',
                  style: TextStyle(fontSize: context.tvSp(14), color: TvTheme.textSecondary),
                ),
                SizedBox(height: context.tvDp(20)),
              ],
              const CircularProgressIndicator(color: TvTheme.focusColor),
              SizedBox(height: context.tvDp(16)),
              Text(
                'M1 导航验证页 · TV 播放页将在 M2 提供\n按返回键/OK 回到列表',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: context.tvSp(14), color: TvTheme.textSecondary, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
