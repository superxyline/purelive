import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:pure_live/core/common/core_log.dart';

/// 弹幕帧串行解码队列：把大帧的 CPU 密集解析（解压 / 协议解码）移出 UI 线程，
/// 同时保证消息分发顺序与网络到达顺序一致。
///
/// 机制（对齐 wzgrx PR #235 的思路，按本地架构简化）：
/// - 队列空闲时同步解码（认证 / 心跳 / ack 延迟不受影响）；
/// - 队列忙时入队，由单个 drain 循环逐帧 `await` 解码，天然保序；
/// - 解码函数可以内部用 [Isolate.run] 卸载重活，失败自动回退同步路径；
/// - 积压超过 [backlogLimit] 字节时熔断：解码跟不上（极端风控帧风暴）时
///   丢弃后续帧而不是无限吃内存，下一帧正常弹幕仍继续。
class FrameDecodeQueue {
  FrameDecodeQueue({this.backlogLimit = 16 << 20});

  /// 未完成帧的累计字节数上限。
  final int backlogLimit;

  final Queue<List<int>> _pending = Queue();
  int _pendingBytes = 0;
  bool _draining = false;
  bool _tripped = false;

  /// 队列是否空闲（无在解码帧、无积压）。
  bool get isIdle => !_draining && _pending.isEmpty;

  /// 入队一帧。若队列空闲则立即同步解码，否则排队等待串行处理。
  void enqueue(List<int> frame, Future<void> Function(List<int> frame) decode) {
    if (_tripped) return;
    if (isIdle) {
      _drainOne(frame, decode);
      return;
    }
    _pendingBytes += frame.length;
    if (_pendingBytes > backlogLimit) {
      _tripped = true;
      CoreLog.w('FrameDecodeQueue backlog exceeded $backlogLimit bytes, dropping frames');
      _pending.clear();
      _pendingBytes = 0;
      return;
    }
    _pending.add(frame);
    _drain(decode);
  }

  Future<void> _drain(Future<void> Function(List<int> frame) decode) async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        final frame = _pending.removeFirst();
        _pendingBytes -= frame.length;
        await _drainOne(frame, decode);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainOne(List<int> frame, Future<void> Function(List<int> frame) decode) async {
    try {
      await decode(frame);
    } catch (error) {
      // 坏帧只终止当前这条消息：下一帧正常弹幕仍然继续进入列表与画面。
      CoreLog.error(error);
    }
  }
}

/// 在独立 isolate 中运行 [task]，失败或环境不支持时回退同步执行。
/// [task] 闭包只允许捕获可跨 isolate 传输的数据（Uint8List 等），
/// 且引用的函数必须是静态 / 顶层函数。
Future<T> runInIsolateOrSync<T>(FutureOr<T> Function() task, T Function() fallback) async {
  try {
    return await Isolate.run(task);
  } catch (error) {
    CoreLog.w('isolate decode fallback: $error');
    return fallback();
  }
}
