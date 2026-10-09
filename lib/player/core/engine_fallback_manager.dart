import 'package:flutter/foundation.dart';
import '../models/player_engine.dart';
import '../models/player_exception.dart';
import '../models/player_error_type.dart';

/// release 构建下 dart:developer 的 log 不输出到 logcat——改走 debugPrint，
/// 保证换线/降级/卡死等关键诊断日志在 logcat（I/flutter）里可见。
void log(String message, {String? name, DateTime? time, Object? error, StackTrace? stackTrace}) {
  final prefix = name != null ? '[$name] ' : '';
  final err = error != null ? ' | error=$error' : '';
  debugPrint('$prefix$message$err', wrapWidth: 160);
}

class EngineFallbackManager {
  EngineFallbackManager({required this.defaultEngine, this.maxRetryCount = 2, required this.supportedEngines});
  final List<PlayerEngine> supportedEngines;

  final PlayerEngine defaultEngine;
  final int maxRetryCount;

  final Map<PlayerEngine, int> _retryMap = {};
  final Set<PlayerEngine> _permanentlyFailed = {};

  late final List<PlayerEngine> _priority = [
    defaultEngine,
    ...PlayerEngine.values,
  ].where((e) => supportedEngines.contains(e)).toList();

  bool shouldFallback(PlayerException error) {
    switch (error.type) {
      case PlayerErrorType.codec:
      case PlayerErrorType.native:
      case PlayerErrorType.texture:
      case PlayerErrorType.initialization:
      case PlayerErrorType.source:
        return true;
      default:
        return false;
    }
  }

  Future<PlayerEngine> fallback(PlayerEngine current, PlayerException error) async {
    if (supportedEngines.length <= 1) {
      return defaultEngine;
    }
    final currentRetry = _retryMap[current] ?? 0;
    final nextRetry = currentRetry + 1;
    _retryMap[current] = nextRetry;

    if (nextRetry < maxRetryCount) {
      return current;
    }

    _permanentlyFailed.add(current);
    for (final engine in _priority) {
      if (!_permanentlyFailed.contains(engine)) {
        log("🔄 引擎降级成功: $current -> $engine");
        _retryMap[engine] = 0;
        return engine;
      }
    }

    resetAll();
    throw error;
  }

  void reset(PlayerEngine engine) {
    _retryMap[engine] = 0;
    _permanentlyFailed.remove(engine);
  }

  void resetAll() {
    _retryMap.clear();
    _permanentlyFailed.clear();
  }
}
