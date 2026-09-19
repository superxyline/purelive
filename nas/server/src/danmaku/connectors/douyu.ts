import WebSocket, { type RawData } from 'ws';
import { registerConnector, type DanmakuConnector, type DanmakuSender } from '../registry';

const DOUYU_WS_URL = 'wss://danmuproxy.douyu.com:8506';
const HEARTBEAT_INTERVAL_MS = 45_000;

/** 斗鱼 STT：type@=key/…，嵌套 @A=@ / @S=/，数组用 //。 */
function sttToJObject(str: string): unknown {
  if (str.includes('//')) {
    const result: unknown[] = [];
    for (const field of str.split('//')) {
      if (!field) continue;
      result.push(sttToJObject(field));
    }
    return result;
  }
  if (str.includes('@=')) {
    const result: Record<string, unknown> = {};
    for (const field of str.split('/')) {
      if (!field) continue;
      const sep = field.indexOf('@=');
      if (sep <= 0) continue;
      const k = field.slice(0, sep);
      const v = unscapeSlashAt(field.slice(sep + 2));
      result[k] = sttToJObject(v);
    }
    return result;
  }
  if (str.includes('@A=')) {
    return sttToJObject(unscapeSlashAt(str));
  }
  return unscapeSlashAt(str);
}

function unscapeSlashAt(str: string): string {
  return str.replaceAll('@S', '/').replaceAll('@A', '@');
}

function serializeDouyu(body: string): Buffer {
  // 客户端 type=689；两个 4B 总长 + 2B type + 1B encrypt + 1B reserved + body + 结尾 \0
  const payload = Buffer.from(body, 'utf8');
  const total = 4 + 4 + payload.length + 1;
  const header = Buffer.alloc(12);
  header.writeUInt32LE(total, 0);
  header.writeUInt32LE(total, 4);
  header.writeUInt16LE(689, 8);
  header.writeUInt8(0, 10);
  header.writeUInt8(0, 11);
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
    const bodyStart = offset + 12;
    packets.push(buffer.subarray(bodyStart, bodyStart + bodyLength).toString('utf8'));
    offset += frameLength;
  }
  return packets;
}

class DouyuDanmakuConnector implements DanmakuConnector {
  private ws: WebSocket | null = null;
  private heartbeatTimer: NodeJS.Timeout | null = null;
  private roomId: string;

  constructor(
    roomId: string,
    _danmakuData: unknown,
    private readonly send: DanmakuSender,
  ) {
    this.roomId = roomId;
  }

  async start(): Promise<void> {
    this.ws = new WebSocket(DOUYU_WS_URL);
    this.ws.on('open', () => {
      this.ws?.send(serializeDouyu(`type@=loginreq/roomid@=${this.roomId}/`));
      this.ws?.send(serializeDouyu(`type@=joingroup/rid@=${this.roomId}/gid@=-9999/`));
      this.startHeartbeat();
    });
    this.ws.on('message', (data) => this.decode(toBuffer(data)));
    this.ws.on('error', () => {});
    this.ws.on('close', () => this.stopHeartbeat());
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.ws?.send(serializeDouyu('type@=mrkl/'));
    }, HEARTBEAT_INTERVAL_MS);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = null;
  }

  private decode(data: Buffer): void {
    for (const packet of deserializePackets(data)) {
      try {
        const json = sttToJObject(packet) as Record<string, unknown> | unknown[];
        if (Array.isArray(json) || json === null || typeof json !== 'object') continue;
        const jsonData = json as Record<string, unknown>;
        const type = String(jsonData['type'] ?? '');
        if (type === 'chatmsg') {
          if (jsonData['dms'] == null) continue;
          const packetRoomId = String(jsonData['rid'] ?? '');
          if (packetRoomId && this.roomId && packetRoomId !== this.roomId) continue;
          this.send({
            type: 'msg',
            userName: String(jsonData['nn'] ?? ''),
            userId: String(jsonData['uid'] ?? ''),
            message: String(jsonData['txt'] ?? ''),
          });
        } else if (type === 'dgb') {
          const giftId = String(jsonData['gfid'] ?? '');
          const giftCount = Number.parseInt(String(jsonData['gs'] ?? '1'), 10) || 1;
          const giftName = String(jsonData['gfn'] ?? jsonData['gn'] ?? '').trim();
          this.send({
            type: 'gift',
            userName: String(jsonData['nn'] ?? ''),
            userId: String(jsonData['uid'] ?? ''),
            giftName,
            giftCount,
            giftPrice: 1,
            totalCoin: giftCount,
            message: giftName,
            subMessage: giftId,
          });
        }
      } catch (_) {}
    }
  }

  stop(): void {
    this.stopHeartbeat();
    try {
      this.ws?.close();
    } catch (_) {}
    this.ws = null;
  }
}

function toBuffer(data: RawData): Buffer {
  if (Buffer.isBuffer(data)) return data;
  if (Array.isArray(data)) return Buffer.concat(data);
  return Buffer.from(data as ArrayBuffer);
}

registerConnector('douyu', (roomId, danmakuData, send) => new DouyuDanmakuConnector(roomId, danmakuData, send));
