class GlobalPlayerState {
  static final GlobalPlayerState _instance = GlobalPlayerState._internal();
  factory GlobalPlayerState() => _instance;
  GlobalPlayerState._internal();

  String? _currentRoomId;
  PlayerInstanceState? _currentState;

  /// 设置当前房间，并返回其状态（总是全新或复用当前）
  PlayerInstanceState setCurrentRoom(String roomId) {
    if (_currentRoomId != roomId) {
      _currentRoomId = roomId;
      _currentState = PlayerInstanceState();
    }
    return _currentState!;
  }

  /// 获取当前房间状态（必须先调用 setCurrentRoom）
  PlayerInstanceState getCurrentState() {
    if (_currentState == null) {
      throw StateError('Must call setCurrentRoom first!');
    }
    return _currentState!;
  }

  /// 可选：手动清除（例如退出播放页）
  void clear() {
    _currentRoomId = null;
    _currentState = null;
  }
}

class PlayerInstanceState {
  bool isFullscreen = false;
  bool isWindowFullscreen = false;
}
