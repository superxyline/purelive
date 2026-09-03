# 斗鱼弹幕发送功能分析与实现方案

## 一、协议分析

### 1.1 斗鱼 WebSocket 弹幕协议概述

斗鱼弹幕系统使用自定义的 **STT (Serialized Tag Text)** 协议，通过 WebSocket 传输。

**二进制帧格式：**
```
[4字节 LE] payload_len ( = 4 + 4 + body_utf8.len + 1 )
[4字节 LE] payload_len (重复)
[2字节 LE] 689         (客户端→服务端标识)
[1字节]    0           (加密标志, 0=不加密)
[1字节]    0           (保留)
[N字节]    UTF-8 body  (STT 文本)
[1字节]    0x00        (尾部空终止符)
```

**STT 文本格式：**
```
key1@=value1/key2@=value2/...
```
- `/` 分隔键值对
- `@=` 分隔键和值
- 嵌套: 值本身也可以是 STT 格式
- 转义: `/` → `@S`, `:` → `@A`, `@` → `@A`

### 1.2 当前已有代码分析

**`DouyuDanmaku` 类 (lib/core/danmaku/douyu_danmaku.dart)：**
- ✅ WebSocket 连接: `wss://danmuproxy.douyu.com:8506`
- ✅ 序列化: `serializeDouyu(body)` — 已实现完整的二进制帧封装
- ✅ 反序列化: `deserializeDouyuPackets(buffer)` — 支持多包拆分
- ✅ STT 解析: `sttToJObject(str)` — STT → Map 转换
- ✅ 登录: `joinRoom(roomId)` — 发送 `loginreq` + `joingroup`
- ✅ 心跳: `heartbeat()` — 发送 `mrkl/`
- ❌ 发送弹幕: 未实现
- ❌ 登录响应解析: 未提取 uid / token 等认证字段

**`DouyuSite` 类 (lib/core/site/douyu_site.dart)：**
- ✅ `sendDanmaku()` 方法存在，但当前返回 "不支持"
- ✅ Cookie 管理: `SettingsService.to.cookieManager.douyuCookie`
- ✅ 登录检测: Cookie 中包含 `acf_uid` + `acf_stk` 表示已登录

**`LivePlayController` (lib/modules/live_play/controllers/live_play_controller.dart)：**
- ✅ `sendLiveDanmaku()` 方法存在
- ❌ 当前硬编码只支持 Bilibili: `if (site != Sites.bilibiliSite) return false`

### 1.3 斗鱼 WebSocket 弹幕发送流程

经过协议分析，斗鱼发送弹幕需要以下步骤：

#### 步骤1: 建立 WebSocket 连接
```
wss://danmuproxy.douyu.com:8506
```

#### 步骤2: 发送登录请求 (loginreq)
```
type@=loginreq/roomid@={room_id}/devid@={device_id}/rt@={timestamp}/ver@=21952015/vk@={vk}/
```
- `devid`: UUID 格式设备ID
- `rt`: 当前秒级时间戳
- `vk`: MD5(roomid + devid + rt + "123456789012345678901234567890")

#### 步骤3: 接收登录响应 (loginres)
服务器返回包含 `uid` (服务器分配的匿名/登录用户ID) 等字段。

#### 步骤4: 加入分组 (joingroup)
```
type@=joingroup/rid@={room_id}/gid@=-9999/
```

#### 步骤5: 发送弹幕 (chatmessage)
```
type@=chatmessage/roomid@={room_id}/content@={message}/col@=0/pt@=0/sea@=0/sankt@=0/uid@={uid}/nn@={nickname}/txt@={message}/ic@={icon}/level@={level}/le@={exp}/br@={badge_level}/dms@=5/cst@={timestamp_ms}/
```

**关键字段说明：**
- `uid`: 登录后服务器分配的用户ID（从 loginres 获取）
- `nn`: 昵称
- `txt`: 弹幕内容
- `content`: 弹幕内容（同 txt）
- `col`: 颜色 (0=默认)
- `dms`: 弹幕类型 (5=普通弹幕)
- `cst`: 客户端时间戳（毫秒）

### 1.4 认证方式分析

斗鱼有多种认证路径：

**路径A: WebSocket 登录认证（推荐）**
- 通过 `loginreq` 携带设备信息和签名
- 服务器返回 `loginres` 包含 `uid`
- 无需 Cookie，匿名用户也可以发送（受限）

**路径B: Cookie 认证 + WebSocket**
- 使用用户 Cookie 中的 `acf_uid`、`acf_stk`
- 在 `loginreq` 中携带这些凭证
- 服务器返回已登录用户的 `uid`
- 可以发送弹幕（需登录）

**路径C: HTTP API（备选）**
- POST 到斗鱼 Web API
- 需要完整 Cookie 认证
- 与 WebSocket 方式二选一

## 二、实现方案

### 2.1 方案选择

**选择: WebSocket 方式 (路径B)**

理由：
1. 复用现有的 `DouyuDanmaku` WebSocket 连接
2. 代码改动最小，不需要新建连接
3. 已有 `serializeDouyu()` 和 `webScoketUtils?.sendMessage()` 基础设施
4. 项目中 Cookie 已经存储，可以直接使用

### 2.2 需要修改的文件

| 文件 | 改动类型 | 说明 |
|------|---------|------|
| `lib/core/danmaku/douyu_danmaku.dart` | 扩展 | 添加 `sendChatMessage()` 方法 |
| `lib/core/site/douyu_site.dart` | 实现 | 实现 `sendDanmaku()` 方法 |
| `lib/modules/live_play/controllers/live_play_controller.dart` | 修改 | 启用斗鱼弹幕发送支持 |
| `lib/common/models/live_room.dart` | 只读 | 验证模型结构 |
| `test/douyu_danmaku_protocol_test.dart` | 扩展 | 添加发送协议测试 |

### 2.3 详细实现步骤

#### Step 1: 扩展 `DouyuDanmaku` — 添加发送能力

在 `DouyuDanmaku` 类中添加：
- `sendChatMessage(String content)` 方法
- 解析 `loginres` 响应以获取 `uid`
- 支持在登录时携带 Cookie 认证信息

#### Step 2: 实现 `DouyuSite.sendDanmaku()`

```dart
Future<(bool, String)> sendDanmaku({required String roomId, required String message}) async {
  // 1. 检查 Cookie
  // 2. 通过独立的 WebSocket 连接发送
  // 3. 返回结果
}
```

#### Step 3: 修改 `LivePlayController.sendLiveDanmaku()`

移除 Bilibili 独占限制，添加斗鱼支持。

### 2.4 测试策略

1. **单元测试**: 验证序列化/反序列化正确性
2. **集成测试**: 验证登录→发送→回显完整流程
3. **探针脚本**: Python 脚本验证协议可行性

## 三、风险评估

1. **限流风险**: 斗鱼可能对弹幕发送频率有限制
2. **封号风险**: 需要合规使用，不应自动化刷屏
3. **协议变更**: 斗鱼可能更新协议，需要持续维护
4. **Cookie 过期**: 用户 Cookie 可能过期，需要提示重新登录
