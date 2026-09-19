/**
 * 虎牙弹幕 Connector（移植自 lib/core/danmaku/huya_danmaku.dart）。
 * Tars 二进制协议：wss://wsapi.huya.com，注册 live:{uid}/chat:{uid} 分组，
 * 心跳 60s，下行 uri 1400 弹幕 / 8006 人气 / 6501 礼物（编解码见 tars_codec.ts）。
 * 弹幕参数 {uid, topSid, subSid} 取自 huya site 的 danmakuData；未提供时现场拉房间详情。
 */
import WebSocket from 'ws';
import type { DanmakuMessageJson } from '../../protocol';
import { getSite } from '../../sites';
import { registerConnector, type DanmakuSender } from '../registry';
import {
  buildHuyaHeartbeat,
  buildHuyaRegisterGroup,
  decodeHuyaAttendeeCount,
  decodeHuyaChat,
  decodeHuyaFrame,
  decodeHuyaGift,
} from './tars_codec';

export interface HuyaDanmakuArgs {
  uid: number;
  topSid: number;
  subSid: number;
}

export class HuyaConnector {
  private ws: WebSocket | null = null;
  private heartbeatTimer: NodeJS.Timeout | null = null;
  private closed = false;

  constructor(
    private readonly roomId: string,
    args: unknown,
    private readonly send: DanmakuSender,
  ) {
    this.args = this.parseArgs(args);
  }

  private args?: HuyaDanmakuArgs;

  private parseArgs(args: unknown): HuyaDanmakuArgs | undefined {
    if (args != null && typeof args === 'object') {
      const a = args as Partial<HuyaDanmakuArgs>;
      if (a.uid != null && Number(a.uid) > 0) {
        return { uid: Number(a.uid), topSid: Number(a.topSid ?? 0), subSid: Number(a.subSid ?? 0) };
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

  /** danmakuData 缺失时从 site 详情兜底拿 {uid, topSid, subSid}。 */
  private async resolveArgs(): Promise<HuyaDanmakuArgs> {
    const detail = await getSite('huya').getRoomDetail(this.roomId);
    const args = this.parseArgs(detail.danmakuData);
    if (args == null) {
      throw new Error(`huya danmaku args missing for room ${this.roomId}`);
    }
    return args;
  }

  private connect(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      if (this.closed) return resolve();
      const ws = new WebSocket('wss://wsapi.huya.com');
      this.ws = ws;
      ws.binaryType = 'arraybuffer';

      ws.on('open', () => {
        if (this.closed) {
          ws.close();
          return;
        }
        // 注册分组 + 立即心跳（Dart joinRoom/heartbeat）
        ws.send(buildHuyaRegisterGroup(this.args!.uid));
        ws.send(buildHuyaHeartbeat());
        this.heartbeatTimer = setInterval(() => {
          try {
            ws.send(buildHuyaHeartbeat());
          } catch {
            // 发送失败交由 close 处理
          }
        }, 60_000);
        resolve();
      });

      ws.on('message', (data: WebSocket.RawData) => {
        try {
          const bytes = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data as Buffer);
          this.decodeMessage(bytes);
        } catch {
          // 单帧解析失败不中断连接
        }
      });

      ws.on('error', (err) => {
        if (!this.closed) reject(err);
      });

      ws.on('close', () => {
        if (this.heartbeatTimer) {
          clearInterval(this.heartbeatTimer);
          this.heartbeatTimer = null;
        }
      });
    });
  }

  private decodeMessage(data: Uint8Array): void {
    const { pushes } = decodeHuyaFrame(data);
    for (const push of pushes) {
      this.decodePush(push.uri, push.msg);
    }
  }

  private decodePush(uri: number, payload: Uint8Array): void {
    if (uri === 1400) {
      // 弹幕（fontColor 不进统一协议：统一协议的弹幕为默认白色）
      const message = decodeHuyaChat(payload);
      this.send({
        type: 'msg',
        userName: message.nickName,
        message: message.content,
      });
    } else if (uri === 8006) {
      // 人气（口径与列表热度一致）
      const attendeeCount = decodeHuyaAttendeeCount(payload);
      this.send({ type: 'online', onlineCount: attendeeCount });
    } else if (uri === 6501) {
      // 礼物（SendItemSubBroadcastPacket）
      try {
        const gift = decodeHuyaGift(payload);
        const giftName = gift.sPropsName.trim() || String(gift.iItemType);
        const count = gift.iItemCount > 0 ? gift.iItemCount : 1;
        const price = gift.lPayTotal > 0 ? gift.lPayTotal : 1;
        this.send({
          type: 'gift',
          userName: gift.sSenderNick,
          message: giftName,
          giftName,
          giftCount: count,
          giftPrice: price,
          giftColor: '#FFC800', // 金色表示礼物（LiveMessageColor(255,200,0)）
        });
      } catch {
        // 礼物解析失败静默丢弃
      }
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

registerConnector('huya', (roomId, danmakuData, send) => new HuyaConnector(roomId, danmakuData, send));
