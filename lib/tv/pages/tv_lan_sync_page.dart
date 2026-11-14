import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';

import '../core/tv_theme.dart';

/// TV 局域网设备互推页：列出广播发现的本网络内 PureLive 设备，
/// 选中后按 OK 推送关注与登录态（对端确认后合并）。
/// 键位：↑↓ 选设备，OK 推送，返回退出。
class TvLanSyncPage extends StatefulWidget {
  const TvLanSyncPage({super.key});

  @override
  State<TvLanSyncPage> createState() => _TvLanSyncPageState();
}

class _TvLanSyncPageState extends State<TvLanSyncPage> {
  int _index = 0;
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<LanDiscoveryService>()) {
      LanDiscoveryService.to.peers.listen((_) => mounted ? setState(() {}) : null);
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
    final peers = Get.isRegistered<LanDiscoveryService>() ? LanDiscoveryService.to.peers.toList() : <LanPeer>[];

    if (goBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (_index - 1).clamp(0, peers.isEmpty ? 0 : peers.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (peers.isNotEmpty) setState(() => _index = (_index + 1).clamp(0, peers.length - 1));
      return KeyEventResult.handled;
    }
    if (confirm && !_pushing && peers.isNotEmpty && _index < peers.length) {
      _push(peers[_index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _push(LanPeer peer) async {
    setState(() => _pushing = true);
    try {
      final service = Get.find<LanDiscoveryService>();
      final payload = Get.find<BackupController>().exportTransferData();
      final ok = await service.pushTo(peer, payload);
      if (!mounted) return;
      setState(() => _pushing = false);
      _toast(ok ? '已推送到 ${peer.name}（对端确认后合并）' : '推送失败（对端拒绝或不可达）');
    } catch (_) {
      if (mounted) setState(() => _pushing = false);
      _toast('推送失败');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final service = Get.isRegistered<LanDiscoveryService>() ? LanDiscoveryService.to : null;
    final peers = service?.peers.toList() ?? const <LanPeer>[];
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Padding(
          padding: EdgeInsets.all(context.tvDp(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '局域网设备互推',
                style: TextStyle(fontSize: context.tvSp(24), fontWeight: FontWeight.w700, color: TvTheme.textPrimary),
              ),
              SizedBox(height: context.tvDp(6)),
              Text(
                '同一 Wi-Fi 下运行 PureLive 的设备会自动出现在这里；选中后按 OK 推送本机的关注与登录态，对方确认后合并（已有的不重复）。',
                style: TextStyle(fontSize: context.tvSp(14), color: TvTheme.textSecondary, height: 1.6),
              ),
              SizedBox(height: context.tvDp(16)),
              if (peers.isEmpty)
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: context.tvDp(18),
                        height: context.tvDp(18),
                        child: const CircularProgressIndicator(strokeWidth: 2, color: TvTheme.focusColor),
                      ),
                      SizedBox(width: context.tvDp(10)),
                      Text(
                        '正在搜索局域网设备...',
                        style: TextStyle(fontSize: context.tvSp(16), color: TvTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (context, i) {
                      final peer = peers[i];
                      final highlighted = i == _index;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _index = i);
                          _push(peer);
                        },
                        child: Container(
                          margin: EdgeInsets.only(bottom: context.tvDp(10)),
                          padding: EdgeInsets.symmetric(horizontal: context.tvDp(18), vertical: context.tvDp(14)),
                          decoration: BoxDecoration(
                            color: highlighted ? TvTheme.focusColor.withValues(alpha: 0.85) : TvTheme.subtleFill,
                            borderRadius: BorderRadius.circular(context.tvDp(12)),
                            border: Border.all(
                              color: highlighted ? TvTheme.focusColor : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                peer.type == 'tv'
                                    ? Icons.tv_rounded
                                    : peer.type == 'tablet'
                                        ? Icons.tablet_rounded
                                        : Icons.smartphone_rounded,
                                size: context.tvDp(22),
                                color: highlighted ? Colors.white : TvTheme.textSecondary,
                              ),
                              SizedBox(width: context.tvDp(12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      peer.name,
                                      style: TextStyle(
                                        fontSize: context.tvSp(16),
                                        fontWeight: FontWeight.w600,
                                        color: highlighted ? Colors.white : TvTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      peer.ip,
                                      style: TextStyle(
                                        fontSize: context.tvSp(12),
                                        color: highlighted ? Colors.white70 : TvTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_pushing && highlighted)
                                SizedBox(
                                  width: context.tvDp(16),
                                  height: context.tvDp(16),
                                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              else
                                Text(
                                  '按 OK 推送',
                                  style: TextStyle(
                                    fontSize: context.tvSp(12),
                                    color: highlighted ? Colors.white : TvTheme.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              Text(
                '按返回键退出',
                style: TextStyle(fontSize: context.tvSp(12), color: TvTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
