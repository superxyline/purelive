# 斗鱼弹幕发送调研记录（2026-09-25）

> 本轮通过 CDP 驱动 Edge 抓取网页真实 WS 帧完成的协议调研。目标是打通 WebUI / 安卓端的斗鱼弹幕发送。
> 状态：**协议 80% 破解，卡在 vk 算法与 chatmessage 字段集的稳定抓取**。

## 一、核心结论

1. **老通道已死**：`wss://danmuproxy.douyu.com:8506` + `chatmessage` 的旧协议被斗鱼"防御塔"反作弊（`defense_tower_session` 包）**静默丢弃**——连接正常、认证正常、房间正常，弹幕就是不下发。本机家庭宽带 IP 与 NAS IP 双环境验证一致，与 IP 无关。
2. **网页现在走新通道**：`wss://wsproxy.douyu.com:6672/6673`（多端口），**帧格式与老协议相同**（4B+4B LE 长度 + 2B magic=689 + 1B encrypt + 1B reserved + STT body + \0），现有编解码器全部复用。
3. **新 loginreq 全字段**（网页真实帧，CDP Network.webSocketFrameSent 抓取）：

```
type@=loginreq/roomid@=24422/dfl@=/username@=qq_DTXHkFw7/password@=/
ltkid@=107175570/biz@=1/stk@=<acf_stk>/devid@=<acf_did>/ct@=0/pt@=2/
cvr@=0/tvr@=7/apd@=/jwt@=<acf_jwt_token>/rt@=<unix秒>/vk@=<md5待破解>/
ver@=20220825/aver@=218101901/dmbt@=edge/dmbv@=153/
```

- `username/ltkid/stk/devid/jwt` **全部直接来自 cookie** 的 `acf_username/acf_ltkid/acf_stk/acf_did/acf_jwt_token`，无需生成。
- **`jwt` 是关键鉴权字段**（`{"alg":"md5","typ":"JWT"}.{"aud":["dm"],"ltkid":...,"stk":...,"uid":...,"exp":...}` 签名段为 md5）。
- **`vk` 是唯一需要算法的字段**。vk 随 rt 每次变化。

4. **vk 算法未破解**。已有样本（roomid=24422, devid=ad345ba38cfca51b48b5140700041701, username=qq_DTXHkFw7, ltkid=107175570, stk=0c0f7849ec7ac575, uid=27047486）：

| rt | vk |
|---|---|
| 1790344212 | 9bc0298f652859ca1a82fd8a2032c229 |
| 1790344223 | e2b84db4a300510a3d298c3a2445c2b3 |

   已排除：md5(roomid+devid+rt) 各排列 × 盐{空、"1234…30位"、"7st71OC2kE4vR HCI04Lo3Z6dGw9p"、…}、插入 stk/ltkid/uid/username/jwt/guid 的组合、HmacMD5 变体——**全部未命中**。vk 大概率在页面 JS 内生成（混淆），需要逆向页面 JS 的 vk 函数。

5. **chatmessage 新字段集**（网页发出帧，抓到一次）：

```
...pe@=0/content@=<内容>/col@=0/type@=chatmessage/dy@=<acf_did>/sender@=<uid>/
ifs@=0/nc@=0/dat@=0/rev@=0/tts@=<unix秒>/admzq@=0/cst@=<unix毫秒>/
```

- **`type@=chatmessage` 不在帧首**（前面还有字段，需完整帧确认是否另有前缀结构）；
- 没有 `roomid/nn/txt/uid`，改用 `dy@`（设备号）与 `sender@`（uid）；
- `content` 直接跟在开头部分。
- 只抓到一次（页面发送路径不稳定，受会话状态影响），需要多抓几条样本确认完整结构。

## 二、错误码记录

| 错误码 | 场景 | 含义 |
|---|---|---|
| `error/code@=4206` | 旧 cookie（JWT 已过期 9-04）注入网页会话 | 凭证过期/不匹配 |
| `error/code@=51` | 同上 | 同上 |
| `error/code@=101010220` | wsproxy 新协议缺 vk/vk 为空 | 请求参数校验失败 |
| `error/code@=401000206` | 同上 | 同上 |

## 三、其他关键事实

- **房间号**：斗鱼存在短号（如 810975）与真实号（48699）映射；WS 的 roomid 应使用**真实房间号**。未开播房间收不到弹幕流、发送也被忽略——测试必须用**在播房间**。
- **NAS 托管 cookie 的时效**：斗鱼 JWT 有效期约 7~30 天，过期后所有发送类请求报 4206。托管 cookie 需要定期更新（账号页重新粘贴）。
- **旧通道的 loginreq**：不带认证字段（极简 `roomid`）服务器正常回 loginres（userid=0 游客）；带 `uid/stk/aa1` + `ver@=21952015/vk(30位盐)` 反而不回包——旧格式彻底弃用。
- server 现状（`nas/server/src/auth/douyu_send.ts`）：已部署"诚实版"——老通道 + 回显校验（6s 等 `chatmsg txt=` 回显）+ 每房间 1.2s 节流 + STT 转义（`@`→`@A`、`/`→`@S`，注意转义顺序）+ 准确错误分级。在防御塔拦截下返回"未收到服务器回显"，不再假成功。
- WebUI（`Room.vue`）：发送框 B站+斗鱼显示，前端 1.5s 节流。
- 安卓端：`DouyuChatSender`（551 行 + 36 单测）未接线；集成指南 `docs/DOUYU_DANMAKU_SEND_INTEGRATION.md` 的三处改动仍适用，但实现需换成本文档的新协议。

## 四、下一步路径

1. **逆向页面 JS 的 vk 生成**：CDP 抓页面主 JS bundle，搜 `vk@=`/`rt@=`/`20220825` 定位生成函数；或对页面做 Function hook（hook String.prototype/md5 库入口）在运行时捕获 vk 明文输入——**拿到输入串结构即破解**。
2. **稳定抓取 chatmessage 帧**：登录会话 Fresh 时（cookie 注入后首次 navigate）点击发送，连续抓多条完整帧（含帧头 hex），确认是否有前置结构。
3. server 改造：`douyu_send.ts` 切换 wsproxy:6673 + 新 loginreq（vk 破解后）+ 新 chatmessage 字段集；错误码映射表（4206/51/101010220 → 用户可读文案）。
4. 安卓移植：`DouyuChatSender` 换新协议（帧编解码/MD5 复用现有），接线照集成指南。

## 五、本轮已提交

- `374c6fbb`：douyu_send.ts 回显校验+节流+转义+准确错误（老通道诚实版）；Room.vue 入口恢复。
- 抓帧工具模式：CDP `Network.webSocketFrameSent/Received`（比页面世界 hook 可靠——弹幕 WS 可能跑在 Worker）。
