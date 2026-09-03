# 斗鱼弹幕发送 - 集成指南

## 文件总览

### 新增文件
| 文件 | 说明 |
|------|------|
| `lib/core/danmaku/douyu_chat_sender.dart` | 斗鱼弹幕发送器 (已创建) |
| `test/douyu_chat_sender_test.dart` | 单元测试 (已创建) |

### 需要修改的文件 (3处改动)

---

## 改动 1: `lib/core/site/douyu_site.dart`

### 变更: 实现 `sendDanmaku()` 方法

**当前代码 (第 373-375 行):**
```dart
@override
Future<(bool, String)> sendDanmaku({required String roomId, required String message}) async {
  return (false, i18n('send_danmaku_unsupported'));
}
```

**替换为:**
```dart
@override
Future<(bool, String)> sendDanmaku({required String roomId, required String message}) async {
  try {
    final cookie = SettingsService.to.cookieManager.douyuCookie.v;
    if (cookie.trim().isEmpty) {
      return (false, i18n('send_danmaku_need_login'));
    }
    final sender = DouyuChatSender(cookie: cookie);
    final (ok, info) = await sender.send(
      roomId: roomId,
      content: message,
    );
    return (ok, info);
  } catch (e) {
    return (false, '发送失败：$e');
  }
}
```

**需要在文件头部添加 import:**
```dart
import 'package:pure_live/core/danmaku/douyu_chat_sender.dart';
```

---

## 改动 2: `lib/modules/live_play/controllers/live_play_controller.dart`

### 变更: `sendLiveDanmaku()` 方法移除 Bilibili 独占限制

**当前代码 (第 418-441 行):**
```dart
Future<bool> sendLiveDanmaku(String text) async {
  final content = text.trim();
  if (content.isEmpty) return false;
  if (site != Sites.bilibiliSite) {
    ToastUtil.show(i18n('send_danmaku_unsupported'));
    return false;
  }
  if (SettingsService.to.cookieManager.bilibiliCookie.v.trim().isEmpty) {
    ToastUtil.show(i18n('send_danmaku_need_login'));
    return false;
  }
  final roomId = room.roomId ?? '';
  if (roomId.isEmpty) return false;

  final (ok, info) = await currentSite.liveSite.sendDanmaku(roomId: roomId, message: content);
  if (ok) {
    ToastUtil.show(i18n('send_success'));
    return true;
  }
  ToastUtil.show(info.isEmpty ? i18n('send_failed') : info);
  return false;
}
```

**替换为:**
```dart
Future<bool> sendLiveDanmaku(String text) async {
  final content = text.trim();
  if (content.isEmpty) return false;

  // 平台特定的 Cookie 检查
  if (site == Sites.bilibiliSite) {
    if (SettingsService.to.cookieManager.bilibiliCookie.v.trim().isEmpty) {
      ToastUtil.show(i18n('send_danmaku_need_login'));
      return false;
    }
  } else if (site == Sites.douyuSite) {
    if (SettingsService.to.cookieManager.douyuCookie.v.trim().isEmpty) {
      ToastUtil.show(i18n('send_danmaku_need_login'));
      return false;
    }
  } else {
    ToastUtil.show(i18n('send_danmaku_unsupported'));
    return false;
  }

  final roomId = room.roomId ?? '';
  if (roomId.isEmpty) return false;

  final (ok, info) = await currentSite.liveSite.sendDanmaku(roomId: roomId, message: content);
  if (ok) {
    ToastUtil.show(i18n('send_success'));
    return true;
  }
  ToastUtil.show(info.isEmpty ? i18n('send_failed') : info);
  return false;
}
```

---

## 改动 3: (可选) `lib/common/index.dart`

如果 `DouyuChatSender` 中使用了 `SettingsService`，需要确保 import 路径正确。
由于 `DouyuChatSender` 是独立类，不依赖 SettingsService，此改动可跳过。

---

## 测试验证

### 运行单元测试
```bash
flutter test test/douyu_chat_sender_test.dart
```

### 运行所有斗鱼相关测试
```bash
flutter test test/douyu_danmaku_protocol_test.dart test/douyu_chat_sender_test.dart
```

### 手动验证流程
1. 在 PureLive 中登录斗鱼账号
2. 进入任意直播间
3. 在弹幕输入框输入消息并发送
4. 验证消息出现在直播间弹幕列表中

---

## 协议流程图

```
PureLive App                    Douyu WebSocket Server
    |                                    |
    |  ---- WebSocket Connect -------->  |
    |  <---- Connection Established ---  |
    |                                    |
    |  ---- loginreq (roomId, devid,     |
    |       rt, vk, stk, aa1) -------->  |
    |  <---- loginres (uid, ...) -------  |
    |                                    |
    |  ---- joingroup (roomId, gid) ---> |
    |  <---- (optional response) -------  |
    |                                    |
    |  ---- chatmessage (roomId,        |
    |       content, uid, nn, ...) ----> |
    |  <---- (echo / error) ------------  |
    |                                    |
    |  ---- WebSocket Close -----------> |
```

## 注意事项

1. **频率限制**: 斗鱼对弹幕发送有频率限制，建议发送间隔 > 1秒
2. **Cookie 过期**: 用户 Cookie 过期后需要重新登录
3. **协议变更**: 斗鱼可能更新协议，需要关注并维护
4. **合规使用**: 应提醒用户合规使用弹幕功能
