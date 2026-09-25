import crypto from 'node:crypto';
import WebSocket from 'ws';
import { getCookie } from './cookies';

/**
 * 斗鱼弹幕发送：移植自 lib/core/danmaku/douyu_chat_sender.dart。
 * 流程：连接 wss → loginreq(带 acf_uid/acf_stk/acf_aa1) → loginres → joingroup → chatmessage。
 */

const SERVER_URL = 'wss://danmuproxy.douyu.com:8506';
const SALT = '123456789012345678901234567890';

function extractCookieValue(cookie: string, name: string): string {
  const m = cookie.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return m?.[1] ?? '';
}

function generateDeviceId(): string {
  const hex = crypto.randomBytes(16).toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function generateVk(roomId: string, devid: string, rt: string): string {
  return crypto.createHash('md5').update(`${roomId}${devid}${rt}${SALT}`, 'utf8').digest('hex');
}

/** STT 值转义：必须先转 @ 再转 /（否则 @S/@A 会被二次转义破坏帧结构）。 */
function escapeStt(value: string): string {
  return value.replace(/@/g, '@A').replace(/\//g, '@S');
}

function serializeDouyu(body: string): Buffer {
  const payload = Buffer.from(body, 'utf8');
  const total = 4 + 4 + payload.length + 1;
  const header = Buffer.alloc(12);
  header.writeUInt32LE(total, 0);
  header.writeUInt32LE(total, 4);
  header.writeUInt16LE(689, 8);
  return Buffer.concat([header, payload, Buffer.from([0])]);
}

function deserializePackets(buffer: Buffer): string[] {
  const packets: string[] = [];
  let offset = 0;
  while (offset + 12 <= buffer.length) {
    const fullMsgLength = buffer.readUInt32LE(offset);
    const frameLength = fullMsgLength + 4;
    const bodyLength = fullMsgLength - 9;
    if (fullMsgLength < 9 || bodyLength < 0 || offset + frameLength > buffer.length) break;
    packets.push(buffer.subarray(offset + 12, offset + 12 + bodyLength).toString('utf8'));
    offset += frameLength;
  }
  return packets;
}

/** STT 顶层 type 提取（不完整解析，足够识别 loginres/joingroup） */
function sttType(packet: string): string {
  const m = packet.match(/type@=([^@/]+)@/);
  return m?.[1] ?? '';
}

function sttValue(packet: string, key: string): string {
  const m = packet.match(new RegExp(`${key}@=([^/@]*)`));
  return m?.[1] ?? '';
}

function waitForType(ws: WebSocket, expectedType: string, timeoutMs: number): Promise<string | null> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      ws.off('message', onMessage);
      resolve(null);
    }, timeoutMs);
    const onMessage = (data: WebSocket.RawData): void => {
      const buf = Array.isArray(data) ? Buffer.concat(data) : Buffer.isBuffer(data) ? data : Buffer.from(data as ArrayBuffer);
      for (const packet of deserializePackets(buf)) {
        if (sttType(packet) === expectedType) {
          clearTimeout(timer);
          ws.off('message', onMessage);
          resolve(packet);
          return;
        }
      }
    };
    ws.on('message', onMessage);
  });
}

/**
 * 发送后的结果校验（根治"盲发假成功"）：斗鱼服务器会把发送者自己的弹幕
 * 以 `type=chatmsg, txt=<内容>` 回显到同一条连接；被拒时可能回 `type=error`。
 * 命中回显 → 成功；收到 error → 失败；超时 → 视为被服务器静默丢弃。
 */
async function waitForChatEcho(ws: WebSocket, content: string, timeoutMs: number): Promise<[boolean, string]> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      ws.off('message', onMessage);
      resolve([false, '发送已提交但未收到服务器回显，可能被忽略，请检查直播间']);
    }, timeoutMs);
    const onMessage = (data: WebSocket.RawData): void => {
      const buf = Array.isArray(data) ? Buffer.concat(data) : Buffer.isBuffer(data) ? data : Buffer.from(data as ArrayBuffer);
      for (const packet of deserializePackets(buf)) {
        const type = sttType(packet);
        if (type === 'error') {
          clearTimeout(timer);
          ws.off('message', onMessage);
          resolve([false, `发送被服务器拒绝: ${packet.slice(0, 120)}`]);
          return;
        }
        if (type === 'chatmsg' && sttValue(packet, 'txt') === content) {
          clearTimeout(timer);
          ws.off('message', onMessage);
          resolve([true, '发送成功']);
          return;
        }
      }
    };
    ws.on('message', onMessage);
  });
}

/** 每房间发送节流：斗鱼要求间隔 > 1 秒。 */
const lastSendAtByRoom = new Map<string, number>();

export async function sendDouyuDanmaku(roomId: string, content: string): Promise<[boolean, string]> {
  const cookie = getCookie('douyu');
  const uid = extractCookieValue(cookie, 'acf_uid');
  const stk = extractCookieValue(cookie, 'acf_stk');
  const aa1 = extractCookieValue(cookie, 'acf_aa1');
  if (!uid) return [false, '未登录斗鱼账号，请先在设置中登录'];
  if (!content.trim()) return [false, '弹幕内容不能为空'];

  // 频率限制：同房间 1.2 秒内只放行一条
  const now = Date.now();
  const last = lastSendAtByRoom.get(roomId) ?? 0;
  if (now - last < 1200) return [false, '发送太频繁，请稍后再试'];
  lastSendAtByRoom.set(roomId, now);

  let ws: WebSocket;
  try {
    ws = new WebSocket(SERVER_URL, {
      headers: { 'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
    });
  } catch (e) {
    return [false, `连接斗鱼弹幕服务器失败: ${e}`];
  }

  return new Promise((resolve) => {
    const fail = (msg: string): void => {
      try {
        ws.close();
      } catch (_) {}
      resolve([false, msg]);
    };
    const timeout = setTimeout(() => fail('发送超时'), 25_000);

    ws.on('error', (err) => {
      clearTimeout(timeout);
      fail(`连接错误: ${err.message}`);
    });

    ws.on('open', async () => {
      try {
        // 认证 loginreq（2026-09 实测）：roomid + uid + stk 即可通过认证；
        // 旧实现附加的 devid/rt/ver/vk(30位盐) 会导致服务器整体忽略握手不回包。
        // aa1 段保留（与实测通过的探针格式逐字节一致，缺失时为空值段）。
        ws.send(serializeDouyu(`type@=loginreq/roomid@=${roomId}/uid@=${uid}/stk@=${stk}/aa1@=${aa1}/`));
        ws.send(serializeDouyu(`type@=joingroup/rid@=${roomId}/gid@=-9999/`));

        const loginResponse = await waitForType(ws, 'loginres', 8000);
        if (!loginResponse) return fail('登录响应超时');
        const serverUid = sttValue(loginResponse, 'userid') || sttValue(loginResponse, 'uid');
        if (!serverUid || serverUid === '0') return fail('登录失败：Cookie 可能已过期，请重新登录');

        ws.send(serializeDouyu(`type@=joingroup/rid@=${roomId}/gid@=-9999/`));
        await waitForType(ws, 'joingroup', 3000).catch(() => null);

        const cst = Date.now().toString();
        const safeContent = escapeStt(content);
        const chatBody =
          `type@=chatmessage/roomid@=${roomId}/content@=${safeContent}/col@=0/pt@=0/ct@=${cst}/` +
          `sn@=0/ss@=0/uid@=${serverUid}/nn@=guest/txt@=${safeContent}/level@=1/dms@=5/cst@=${cst}/`;
        ws.send(serializeDouyu(chatBody));

        // 等服务器回显自己的弹幕（type=chatmsg 且 txt 匹配）确认真发出去
        const [ok, msg] = await waitForChatEcho(ws, content, 6000);
        clearTimeout(timeout);
        try {
          ws.close();
        } catch (_) {}
        resolve([ok, msg]);
      } catch (e) {
        clearTimeout(timeout);
        fail(`发送失败: ${e}`);
      }
    });
  });
}
