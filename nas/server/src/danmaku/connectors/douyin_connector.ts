/**
 * 抖音弹幕 Connector（移植自 lib/core/danmaku/douyin_danmaku.dart）。
 * wss URL 带 X-Bogus 签名（sign/douyin.ts）；protobuf 消息用 protobufjs + 手写 JSON
 * schema（字段号从 lib/core/danmaku/proto/douyin.pb.dart 逆向），gzip 用内置 zlib；
 * needAck 回 ack。弹幕参数 {webRid, roomId, userId} 取自 douyin site 的 danmakuData。
 */
import { gunzipSync } from 'zlib';
import protobuf from 'protobufjs';
import WebSocket from 'ws';
import type { DanmakuMessageJson } from '../../protocol';
import { getSite } from '../../sites';
import { K_DOUYIN_UA, getDouyinRequestHeaders } from '../../sites/douyin';
import { evalDouyinSignature } from '../../sign/douyin';
import { registerConnector, type DanmakuSender } from '../registry';

export interface DouyinDanmakuArgs {
  webRid: string;
  roomId: string;
  userId: string;
}

// 字段号与 douyin.pb.dart 一致（int64 全部按 number 读取，弹幕场景精度足够）
const DOUYIN_PROTO = {
  nested: {
    douyin: {
      options: { syntax: 'proto3' as const },
      nested: {
        PushFrame: {
          fields: {
            seqId: { type: 'int64', id: 1 },
            logId: { type: 'int64', id: 2 },
            service: { type: 'int64', id: 3 },
            method: { type: 'int64', id: 4 },
            headersList: { type: 'HeadersList', id: 5, rule: 'repeated' },
            payloadEncoding: { type: 'string', id: 6 },
            payloadType: { type: 'string', id: 7 },
            payload: { type: 'bytes', id: 8 },
          },
        },
        HeadersList: {
          fields: {
            key: { type: 'string', id: 1 },
            value: { type: 'string', id: 2 },
          },
        },
        Response: {
          fields: {
            messages: { type: 'Message', id: 1, rule: 'repeated' },
            cursor: { type: 'string', id: 2 },
            fetchInterval: { type: 'int32', id: 3 },
            now: { type: 'int64', id: 4 },
            internalExt: { type: 'string', id: 5 },
            fetchType: { type: 'int32', id: 6 },
            heartbeatDuration: { type: 'int32', id: 8 },
            needAck: { type: 'bool', id: 9 },
            pushServer: { type: 'string', id: 10 },
            liveCursor: { type: 'string', id: 11 },
            historyNoMore: { type: 'bool', id: 12 },
          },
        },
        Message: {
          fields: {
            method: { type: 'string', id: 1 },
            payload: { type: 'bytes', id: 2 },
            msgId: { type: 'int64', id: 3 },
            msgType: { type: 'int32', id: 4 },
            offset: { type: 'int64', id: 5 },
            needWrdsStore: { type: 'bool', id: 6 },
            wrdsVersion: { type: 'int64', id: 7 },
            wrdsSubKey: { type: 'int32', id: 8 },
          },
        },
        ChatMessage: {
          fields: {
            common: { type: 'Common', id: 1 },
            user: { type: 'User', id: 2 },
            content: { type: 'string', id: 3 },
          },
        },
        RoomUserSeqMessage: {
          fields: {
            common: { type: 'Common', id: 1 },
            total: { type: 'int64', id: 3 },
            popStr: { type: 'string', id: 4 },
            popularity: { type: 'int64', id: 6 },
            totalUser: { type: 'int64', id: 7 },
            totalUserStr: { type: 'string', id: 8 },
            totalStr: { type: 'string', id: 9 },
            onlineUserForAnchor: { type: 'string', id: 10 },
            totalPvForAnchor: { type: 'string', id: 11 },
          },
        },
        GiftMessage: {
          fields: {
            common: { type: 'Common', id: 1 },
            giftId: { type: 'int64', id: 2 },
            groupCount: { type: 'int64', id: 4 },
            repeatCount: { type: 'int64', id: 5 },
            comboCount: { type: 'int64', id: 6 },
            user: { type: 'User', id: 7 },
            repeatEnd: { type: 'int32', id: 9 },
            gift: { type: 'GiftStruct', id: 15 },
          },
        },
        GiftStruct: {
          fields: {
            image: { type: 'Image', id: 1 },
            id: { type: 'int64', id: 5 },
            diamondCount: { type: 'int32', id: 12 },
            name: { type: 'string', id: 16 },
            icon: { type: 'Image', id: 21 },
          },
        },
        Image: {
          fields: {
            urlList: { type: 'string', id: 1, rule: 'repeated' },
            uri: { type: 'string', id: 2 },
          },
        },
        Common: {
          fields: {
            method: { type: 'string', id: 1 },
            msgId: { type: 'int64', id: 2 },
            roomId: { type: 'int64', id: 3 },
            createTime: { type: 'int64', id: 4 },
          },
        },
        User: {
          fields: {
            id: { type: 'int64', id: 1 },
            nickName: { type: 'string', id: 3 },
            AvatarThumb: { type: 'Image', id: 9 },
          },
        },
      },
    },
  },
};

const root = protobuf.Root.fromJSON(DOUYIN_PROTO);
export { DOUYIN_PROTO, root as douyinProtoRoot };
const PushFrame = root.lookupType('douyin.PushFrame');
const Response = root.lookupType('douyin.Response');
const ChatMessage = root.lookupType('douyin.ChatMessage');
const RoomUserSeqMessage = root.lookupType('douyin.RoomUserSeqMessage');
const GiftMessage = root.lookupType('douyin.GiftMessage');

function toNumber(value: unknown): number {
  if (value == null) return 0;
  if (typeof value === 'number') return value;
  const long = value as { toNumber?: () => number };
  if (typeof long.toNumber === 'function') return long.toNumber();
  return Number(value);
}

function toStdString(value: unknown): string {
  return value != null ? String(value) : '';
}

/** Dart DouyinRequestParams：wss 用 Edge UA，接口用 QQBrowser UA。 */
const K_DOUYIN_WSS_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0';
const K_VERSION_CODE = '180800';
const K_SDK_VERSION = '1.0.14-beta.0';

export class DouyinConnector {
  private ws: WebSocket | null = null;
  private heartbeatTimer: NodeJS.Timeout | null = null;
  private closed = false;

  private args?: DouyinDanmakuArgs;

  constructor(
    private readonly roomId: string,
    args: unknown,
    private readonly send: DanmakuSender,
  ) {
    this.args = this.parseArgs(args);
  }

  private parseArgs(args: unknown): DouyinDanmakuArgs | undefined {
    if (args != null && typeof args === 'object') {
      const a = args as Partial<DouyinDanmakuArgs>;
      if (a.webRid != null && String(a.webRid) !== '') {
        return {
          webRid: String(a.webRid),
          roomId: String(a.roomId ?? ''),
          userId: String(a.userId ?? ''),
        };
      }
    }
    return undefined;
  }

  async start(): Promise<void> {
    if (this.args == null) {
      this.args = await this.resolveArgs();
    }
    await this.connect();
  }

  /** danmakuData 缺失时从 site 详情兜底拿 {webRid, roomId, userId}。 */
  private async resolveArgs(): Promise<DouyinDanmakuArgs> {
    const detail = await getSite('douyin').getRoomDetail(this.roomId);
    const args = this.parseArgs(detail.danmakuData);
    if (args == null) {
      throw new Error(`douyin danmaku args missing for room ${this.roomId}`);
    }
    return args;
  }

  /** Dart start：wss URL + X-Bogus signature。 */
  private async buildWssUrl(): Promise<string> {
    const args = this.args!;
    const ts = Date.now();
    const params = new URLSearchParams({
      app_name: 'douyin_web',
      version_code: K_VERSION_CODE,
      webcast_sdk_version: K_SDK_VERSION,
      update_version_code: K_SDK_VERSION,
      compress: 'gzip',
      cursor: `h-1_t-${ts}_r-1_d-1_u-1`,
      host: 'https://live.douyin.com',
      aid: '6383',
      live_id: '1',
      did_rule: '3',
      debug: 'false',
      maxCacheMessageNumber: '20',
      endpoint: 'live_pc',
      support_wrds: '1',
      im_path: '/webcast/im/fetch/',
      user_unique_id: args.userId,
      device_platform: 'web',
      cookie_enabled: 'true',
      screen_width: '1920',
      screen_height: '1080',
      browser_language: 'zh-CN',
      browser_platform: 'Win32',
      browser_name: 'Mozilla',
      browser_version: K_DOUYIN_WSS_UA.replace('Mozilla/', ''),
      browser_online: 'true',
      tz_name: 'Asia/Shanghai',
      identity: 'audience',
      room_id: args.roomId,
      heartbeatDuration: '0',
    });
    const base = `wss://webcast100-ws-web-lq.douyin.com/webcast/im/push/v2/?${params.toString()}`;
    const sign = evalDouyinSignature(args.roomId, args.userId);
    return `${base}&signature=${sign}`;
  }

  private connect(): Promise<void> {
    const doConnect = async (): Promise<WebSocket> => {
      const args = this.args!;
      const url = await this.buildWssUrl();
      const headers = await getDouyinRequestHeaders();
      const ws = new WebSocket(url, {
        headers: {
          'User-Agent': K_DOUYIN_UA,
          Cookie: headers['cookie'] ?? '',
          Origin: 'https://live.douyin.com',
        },
      });
      ws.binaryType = 'arraybuffer';
      // 先挂 error 监听：握手失败（如风控拦截）不能变成未处理异常
      ws.on('error', () => {});
      return ws;
    };

    return new Promise<void>((resolve, reject) => {
      if (this.closed) return resolve();
      let settled = false;
      doConnect()
        .then((socket) => {
          if (this.closed) {
            socket.close();
            return;
          }
          const ws = socket;
          this.ws = ws;

          ws.on('error', (err) => {
            if (!settled) reject(err);
          });

          ws.on('open', () => {
            if (this.closed) {
              ws.close();
              return;
            }
            settled = true;
            // joinRoom 与心跳同帧：PushFrame{payloadType:'hb'}（Dart 同款）
            this.sendHb();
            this.heartbeatTimer = setInterval(() => {
              try {
                this.sendHb();
              } catch {
                // 发送失败交由 close 处理
              }
            }, 10_000);
            resolve();
          });

          ws.on('message', (data: WebSocket.RawData) => {
            try {
              const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data as Buffer);
              this.decodeMessage(bytes, this.args!.roomId);
            } catch {
              // 单帧解析失败不中断连接
            }
          });

          ws.on('close', () => {
            if (this.heartbeatTimer) {
              clearInterval(this.heartbeatTimer);
              this.heartbeatTimer = null;
            }
          });
        })
        .catch((err) => {
          if (!settled) reject(err);
        });
    });
  }

  private sendFrame(frame: Record<string, unknown>): void {
    if (this.ws == null || this.ws.readyState !== WebSocket.OPEN) return;
    const err = PushFrame.verify(frame);
    if (err) throw new Error(err);
    this.ws.send(Uint8Array.from(PushFrame.encode(PushFrame.fromObject(frame)).finish()));
  }

  private sendHb(): void {
    this.sendFrame({ payloadType: 'hb' });
  }

  private sendAck(logId: number, internalExt: string): void {
    this.sendFrame({
      payloadType: 'ack',
      logId,
      payload: Uint8Array.from(Buffer.from(internalExt, 'utf8')),
    });
  }

  private decodeMessage(data: Uint8Array, roomId: string): void {
    const wssPackage = PushFrame.toObject(PushFrame.decode(data), {
      defaults: false,
      longs: Number,
    }) as Record<string, any>;
    const logId = toNumber(wssPackage['logId']);
    const encodedPayload: Uint8Array = wssPackage['payload'] ?? new Uint8Array(0);
    const payloadEncoding = toStdString(wssPackage['payloadEncoding']).toLowerCase();
    const isGzip =
      payloadEncoding === 'gzip' ||
      (encodedPayload.length >= 2 && encodedPayload[0] === 0x1f && encodedPayload[1] === 0x8b);
    const decompressed = isGzip ? gunzipSync(Buffer.from(encodedPayload)) : Buffer.from(encodedPayload);

    const payloadPackage = Response.toObject(Response.decode(decompressed), {
      defaults: false,
      longs: Number,
    }) as Record<string, any>;
    if (payloadPackage['needAck'] === true) {
      this.sendAck(logId, toStdString(payloadPackage['internalExt']));
    }
    for (const msg of payloadPackage['messages'] ?? []) {
      const method = toStdString((msg as Record<string, any>)['method']);
      const payload: Uint8Array = (msg as Record<string, any>)['payload'] ?? new Uint8Array(0);
      if (method === 'WebcastChatMessage') {
        this.onChat(payload, roomId, toStdString(toNumber((msg as Record<string, any>)['msgId'])));
      } else if (method === 'WebcastRoomUserSeqMessage') {
        this.onRoomUserSeq(payload);
      } else if (method === 'WebcastGiftMessage') {
        this.onGift(payload, roomId);
      }
    }
  }

  private onChat(payload: Uint8Array, roomId: string, envelopeMessageId: string): void {
    const chat = ChatMessage.toObject(ChatMessage.decode(payload), { defaults: false, longs: Number }) as Record<string, any>;
    const common = chat['common'] as Record<string, any> | undefined;
    const commonRoomId = common ? toNumber(common['roomId']).toString() : '';
    if (commonRoomId !== '' && commonRoomId !== '0' && commonRoomId !== roomId) return;
    const user = chat['user'] as Record<string, any> | undefined;
    const out: DanmakuMessageJson = {
      type: 'msg',
      userName: user ? toStdString(user['nickName']) : '',
      message: toStdString(chat['content']),
    };
    const avatarList = user?.['AvatarThumb']?.['urlList'];
    if (Array.isArray(avatarList) && avatarList.length > 0) {
      out.face = toStdString(avatarList[0]);
    }
    void envelopeMessageId;
    this.send(out);
  }

  private onRoomUserSeq(payload: Uint8Array): void {
    const roomUserSeq = RoomUserSeqMessage.toObject(RoomUserSeqMessage.decode(payload), {
      defaults: false,
      longs: Number,
    }) as Record<string, any>;
    const onlineText = toStdString(roomUserSeq['onlineUserForAnchor']);
    if (!/[0-9]/.test(onlineText)) return;
    this.send({ type: 'online', onlineCount: parseAudienceNumber(onlineText) });
  }

  private onGift(payload: Uint8Array, roomId: string): void {
    try {
      const giftMsg = GiftMessage.toObject(GiftMessage.decode(payload), {
        defaults: false,
        longs: Number,
      }) as Record<string, any>;
      const common = giftMsg['common'] as Record<string, any> | undefined;
      const commonRoomId = common ? toNumber(common['roomId']).toString() : '';
      if (commonRoomId !== '' && commonRoomId !== '0' && commonRoomId !== roomId) return;

      const gift = (giftMsg['gift'] ?? {}) as Record<string, any>;
      const giftName = gift['name'] != null ? toStdString(gift['name']) : '';
      let giftIdNum = toNumber(giftMsg['giftId']);
      if (giftIdNum === 0 && gift['id'] != null) giftIdNum = toNumber(gift['id']);
      void giftIdNum; // 协议未定义 giftId 字段，仅保留兜底解析
      // 连击数量：repeatCount 为累计值，comboCount 为连击位置，兜底按 1 计
      let giftCount = toNumber(giftMsg['repeatCount']);
      if (giftCount <= 0) giftCount = toNumber(giftMsg['comboCount']);
      if (giftCount <= 0) giftCount = 1;
      const user = (giftMsg['user'] ?? {}) as Record<string, any>;
      // 礼物价值取钻石单价（diamondCount），免费/粉丝团礼物可能为 0
      const unitPrice = gift['diamondCount'] != null ? toNumber(gift['diamondCount']) : 0;

      this.send({
        type: 'gift',
        userName: toStdString(user['nickName']),
        message: giftName,
        giftName,
        giftCount,
        giftPrice: unitPrice > 0 ? unitPrice : 1,
        giftColor: '#FF96A6', // 抖音礼物粉色（LiveMessageColor(255,100,150)）
      });
    } catch {
      // 礼物解析失败静默丢弃
    }
  }

  stop(): void {
    this.closed = true;
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    try {
      this.ws?.close();
    } catch {
      // 忽略关闭异常
    }
    this.ws = null;
  }
}

/** LiveRoom.parseAudienceNumber：处理 "1.2万"/"3.4w"/千分位等展示串。 */
function parseAudienceNumber(text: string): number {
  const raw = text.trim();
  if (raw === '') return 0;
  const match = /^([\d.,]+)\s*([万亿kwKW]?)/.exec(raw);
  if (!match) return 0;
  const value = Number.parseFloat(match[1].replace(/,/g, ''));
  if (Number.isNaN(value)) return 0;
  const ratio =
    match[2] === '万' || match[2] === 'w' || match[2] === 'W'
      ? 10_000
      : match[2] === '亿'
        ? 100_000_000
        : match[2] === 'k' || match[2] === 'K'
          ? 1_000
          : 1;
  return Math.floor(value * ratio);
}

registerConnector('douyin', (roomId, danmakuData, send) => new DouyinConnector(roomId, danmakuData, send));
