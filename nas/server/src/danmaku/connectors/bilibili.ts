import WebSocket, { type RawData } from 'ws';
import zlib from 'node:zlib';
import { registerConnector, type DanmakuConnector, type DanmakuSender } from '../registry';

interface BiliDanmakuArgs {
  roomId: string;
  uid: number | string;
  token: string;
  serverUrls: string[];
  buvid: string;
  cookie: string;
  headers?: Record<string, string>;
}

function writeIntBE(buf: number[], value: number, byteLength: number): void {
  for (let i = byteLength - 1; i >= 0; i--) {
    buf.push((value >> (8 * i)) & 0xff);
  }
}

function readIntBE(data: Uint8Array, offset: number, byteLength: number): number {
  let value = 0;
  for (let i = 0; i < byteLength; i++) {
    value = value * 256 + data[offset + i];
  }
  return value;
}

function encodePacket(body: string | Buffer, op: number): Buffer {
  const data = typeof body === 'string' ? Buffer.from(body, 'utf8') : body;
  const header = Buffer.alloc(16);
  header.writeUInt32BE(data.length + 16, 0);
  header.writeUInt16BE(16, 4);
  header.writeUInt16BE(0, 6); // 协议版本 0=JSON
  header.writeUInt32BE(op, 8);
  header.writeUInt32BE(1, 12);
  return Buffer.concat([header, data]);
}

const AUTH_HEARTBEAT_INTERVAL_MS = 30_000;

class BilibiliDanmakuConnector implements DanmakuConnector {
  private ws: WebSocket | null = null;
  private heartbeatTimer: NodeJS.Timeout | null = null;
  private stopped = false;

  constructor(
    private readonly roomId: string,
    private readonly danmakuData: unknown,
    private readonly send: DanmakuSender,
  ) {}

  async start(): Promise<void> {
    const args = this.danmakuData as Partial<BiliDanmakuArgs> | null;
    const token = args?.token ?? '';
    if (!token) throw new Error('bilibili danmaku: missing token in danmakuData');
    const urls = (args?.serverUrls ?? []).filter((u) => typeof u === 'string' && u.length > 0);
    const url = (urls[0] ?? 'wss://broadcastlv.chat.bilibili.com/sub').replace(/^ws:/, 'wss:');

    const headers: Record<string, string> = {
      'user-agent': args?.headers?.['user-agent'] ?? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
      origin: 'https://live.bilibili.com',
      referer: 'https://live.bilibili.com/',
      ...(args?.cookie ? { cookie: args.cookie } : {}),
    };

    this.ws = new WebSocket(url, { headers });
    this.ws.on('open', () => this.joinRoom());
    this.ws.on('message', (data) => this.decode(toBuffer(data)));
    this.ws.on('error', () => {});
    this.ws.on('close', () => {
      this.stopHeartbeat();
    });
  }

  private joinRoom(): void {
    const args = this.danmakuData as Partial<BiliDanmakuArgs> | null;
    const join = JSON.stringify({
      uid: (args?.uid as number | string) ?? 0,
      roomid: Number(this.roomId) || this.roomId,
      protover: 3,
      buvid: args?.buvid ?? '',
      platform: 'web',
      type: 2,
      key: args?.token ?? '',
    });
    this.ws?.send(encodePacket(join, 7));
    this.startHeartbeat();
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.ws?.send(encodePacket('', 2));
    }, AUTH_HEARTBEAT_INTERVAL_MS);
    this.ws?.send(encodePacket('', 2));
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = null;
  }

  private decode(data: Buffer, depth = 0): void {
    if (depth > 8) return;
    let offset = 0;
    while (offset + 16 <= data.length) {
      const packetLength = readIntBE(data, offset, 4);
      const headerLength = readIntBE(data, offset + 4, 2);
      const protocolVersion = readIntBE(data, offset + 6, 2);
      const operation = readIntBE(data, offset + 8, 4);
      if (headerLength < 16 || packetLength < headerLength || offset + packetLength > data.length) return;
      const body = data.subarray(offset + headerLength, offset + packetLength);

      if (operation === 3) {
        // 人气值
        const online = body.length >= 4 ? readIntBE(body, 0, 4) : 0;
        this.send({ type: 'online', onlineCount: online, message: String(online) });
      } else if (operation === 5) {
        if (protocolVersion === 2 || protocolVersion === 3) {
          try {
            const decoded =
              protocolVersion === 2 ? zlib.inflateSync(body) : zlib.brotliDecompressSync(body);
            this.decode(decoded, depth + 1);
          } catch (_) {}
        } else {
          const text = body.toString('utf8').trim();
          if (text) this.parseMessage(text);
        }
      }
      // operation === 8：认证确认，服务端已 ack；其余 op 忽略
      offset += packetLength;
    }
  }

  private parseMessage(jsonMessage: string): void {
    let obj: any;
    try {
      obj = JSON.parse(jsonMessage);
    } catch (_) {
      return;
    }
    const cmd = String(obj?.cmd ?? '');
    if (cmd.includes('DANMU_MSG')) {
      const info = obj['info'];
      if (!Array.isArray(info) || info.length === 0) return;
      const message = String(info[1] ?? '');
      const meta = Array.isArray(info[2]) ? info[2] : [];
      const userName = String(meta[1] ?? '');
      const userId = String(meta[0] ?? '');
      this.send({ type: 'msg', userName, userId, message });
    } else if (cmd === 'SUPER_CHAT_MESSAGE') {
      const data = obj['data'] ?? {};
      this.send({
        type: 'sc',
        userName: String(data?.user_info?.uname ?? ''),
        face: String(data?.user_info?.face ?? ''),
        message: String(data?.message ?? ''),
        giftPrice: Number(data?.price ?? 0),
        giftColor: String(data?.background_color ?? ''),
      });
    } else if (cmd === 'SEND_GIFT') {
      const data = obj['data'] ?? {};
      const giftName = String(data['giftName'] ?? '');
      const giftCount = Number(data['num'] ?? 1) || 1;
      const action = String(data['action'] ?? '投喂');
      const coinType = String(data['coin_type'] ?? '');
      const totalCoin = Number(data['total_coin'] ?? 0) || 0;
      const unitPrice = Number(data['price'] ?? 0) || 0;
      const price = totalCoin > 0 ? totalCoin : unitPrice > 0 ? unitPrice : 1;
      this.send({
        type: 'gift',
        userName: String(data['uname'] ?? ''),
        userId: String(data['uid'] ?? ''),
        giftName,
        giftCount,
        giftPrice: price,
        totalCoin,
        message: `${action} ${giftName}${coinType === 'silver' ? '（银瓜子）' : ''}`,
      });
    }
    // SEND_GIFT_V2（protobuf）与其他 cmd 暂不解析
  }

  stop(): void {
    this.stopped = true;
    this.stopHeartbeat();
    try {
      this.ws?.close();
    } catch (_) {}
    this.ws = null;
    void this.stopped;
  }
}

function toBuffer(data: RawData): Buffer {
  if (Buffer.isBuffer(data)) return data;
  if (Array.isArray(data)) return Buffer.concat(data);
  return Buffer.from(data as ArrayBuffer);
}

registerConnector('bilibili', (roomId, danmakuData, send) => new BilibiliDanmakuConnector(roomId, danmakuData, send));
