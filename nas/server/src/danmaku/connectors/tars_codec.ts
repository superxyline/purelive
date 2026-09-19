/**
 * Tars 二进制编解码子集（移植自 lib/pkg/tars/codec/tars_input_stream.dart /
 * tars_output_stream.dart，仅保留虎牙弹幕用到的能力）。
 * 类型枚举 TarsStructType：BYTE=0 SHORT=1 INT=2 LONG=3 FLOAT=4 DOUBLE=5
 * STRING1=6 STRING4=7 MAP=8 LIST=9 STRUCT_BEGIN=10 STRUCT_END=11 ZERO_TAG=12 SIMPLE_LIST=13
 */
import type { DanmakuMessageJson } from '../../protocol';

export const TarsType = {
  BYTE: 0,
  SHORT: 1,
  INT: 2,
  LONG: 3,
  FLOAT: 4,
  DOUBLE: 5,
  STRING1: 6,
  STRING4: 7,
  MAP: 8,
  LIST: 9,
  STRUCT_BEGIN: 10,
  STRUCT_END: 11,
  ZERO_TAG: 12,
  SIMPLE_LIST: 13,
} as const;

interface Head {
  type: number;
  tag: number;
}

function newHead(): Head {
  return { type: 0, tag: 0 };
}

export class TarsInputStream {
  private bytes: Uint8Array;
  private position = 0;

  constructor(bytes: Uint8Array, pos = 0) {
    this.bytes = bytes;
    this.position = pos;
  }

  private readHead(hd: Head): number {
    if (this.position >= this.bytes.length) {
      throw new Error('tars: read file to end');
    }
    const b = this.bytes[this.position++];
    hd.type = b & 15;
    hd.tag = (b & (15 << 4)) >> 4;
    if (hd.tag === 15) {
      hd.tag = this.bytes[this.position++];
      return 2;
    }
    return 1;
  }

  private peakHead(hd: Head): number {
    const curPos = this.position;
    const len = this.readHead(hd);
    this.position = curPos;
    return len;
  }

  private skip(len: number): void {
    this.position += len;
  }

  private skipToTag(tag: number): boolean {
    try {
      const hd = newHead();
      for (;;) {
        const len = this.peakHead(hd);
        if (tag <= hd.tag || hd.type === TarsType.STRUCT_END) {
          return tag === hd.tag;
        }
        this.skip(len);
        this.skipFieldWithType(hd.type);
      }
    } catch {
      return false;
    }
  }

  private skipToStructEnd(): void {
    const hd = newHead();
    do {
      this.readHead(hd);
      this.skipFieldWithType(hd.type);
    } while (hd.type !== TarsType.STRUCT_END);
  }

  private skipField(): void {
    const hd = newHead();
    this.readHead(hd);
    this.skipFieldWithType(hd.type);
  }

  private skipFieldWithType(type: number): void {
    switch (type) {
      case TarsType.BYTE:
        this.skip(1);
        break;
      case TarsType.SHORT:
        this.skip(2);
        break;
      case TarsType.INT:
        this.skip(4);
        break;
      case TarsType.LONG:
        this.skip(8);
        break;
      case TarsType.FLOAT:
        this.skip(4);
        break;
      case TarsType.DOUBLE:
        this.skip(8);
        break;
      case TarsType.STRING1: {
        let len = this.bytes[this.position];
        if (len < 0) len += 256;
        this.skip(1 + len);
        break;
      }
      case TarsType.STRING4: {
        const len =
          (this.bytes[this.position] << 24) |
          (this.bytes[this.position + 1] << 16) |
          (this.bytes[this.position + 2] << 8) |
          this.bytes[this.position + 3];
        this.skip(4 + len);
        break;
      }
      case TarsType.MAP: {
        const size = this.readInt(0, true);
        for (let i = 0; i < size * 2; ++i) this.skipField();
        break;
      }
      case TarsType.LIST: {
        const size = this.readInt(0, true);
        for (let i = 0; i < size; ++i) this.skipField();
        break;
      }
      case TarsType.SIMPLE_LIST: {
        const hh = newHead();
        this.readHead(hh);
        if (hh.type !== TarsType.BYTE) throw new Error('tars: skipField with invalid type');
        const size = this.readInt(0, true);
        this.skip(size);
        break;
      }
      case TarsType.STRUCT_BEGIN:
        this.skipToStructEnd();
        break;
      case TarsType.STRUCT_END:
      case TarsType.ZERO_TAG:
        break;
      default:
        throw new Error(`tars: unknown type ${type}`);
    }
  }

  /** 读取整数（int1/int2/int4/int8 统一为 number；int64 精度对弹幕场景足够）。 */
  readInt(tag: number, isRequire = false): number {
    if (this.skipToTag(tag)) {
      const hd = newHead();
      this.readHead(hd);
      switch (hd.type) {
        case TarsType.ZERO_TAG:
          return 0;
        case TarsType.BYTE:
          return this.bytes[this.position++];
        case TarsType.SHORT: {
          const n = (this.bytes[this.position] << 8) | this.bytes[this.position + 1];
          this.position += 2;
          return (n << 16) >> 16;
        }
        case TarsType.INT: {
          const n =
            ((this.bytes[this.position] << 24) |
              (this.bytes[this.position + 1] << 16) |
              (this.bytes[this.position + 2] << 8) |
              this.bytes[this.position + 3]);
          this.position += 4;
          return n | 0;
        }
        case TarsType.LONG: {
          const view = new DataView(this.bytes.buffer, this.bytes.byteOffset + this.position, 8);
          this.position += 8;
          return Number(view.getBigInt64(0));
        }
        default:
          throw new Error('tars: type mismatch');
      }
    } else if (isRequire) {
      throw new Error('tars: require field not exist');
    }
    return 0;
  }

  readString(tag: number, isRequire = false): string {
    if (this.skipToTag(tag)) {
      const hd = newHead();
      this.readHead(hd);
      if (hd.type === TarsType.STRING1) {
        const len = this.bytes[this.position++];
        const s = Buffer.from(this.bytes.subarray(this.position, this.position + len)).toString('utf8');
        this.position += len;
        return s;
      }
      if (hd.type === TarsType.STRING4) {
        const len =
          (this.bytes[this.position] << 24) |
          (this.bytes[this.position + 1] << 16) |
          (this.bytes[this.position + 2] << 8) |
          this.bytes[this.position + 3];
        this.position += 4;
        const s = Buffer.from(this.bytes.subarray(this.position, this.position + len)).toString('utf8');
        this.skip(len);
        return s;
      }
      throw new Error('tars: type mismatch');
    } else if (isRequire) {
      throw new Error('tars: require field not exist');
    }
    return '';
  }

  /** 读取 byte[]（SimpleList 或 List<byte>）。 */
  readBytes(tag: number, isRequire = false): Uint8Array {
    if (this.skipToTag(tag)) {
      const hd = newHead();
      this.readHead(hd);
      if (hd.type === TarsType.SIMPLE_LIST) {
        const hh = newHead();
        this.readHead(hh);
        if (hh.type !== TarsType.BYTE) throw new Error('tars: type mismatch');
        const size = this.readInt(0, true);
        if (size < 0) throw new Error('tars: invalid size');
        const out = this.bytes.subarray(this.position, this.position + size);
        this.position += size;
        return out;
      }
      if (hd.type === TarsType.LIST) {
        const size = this.readInt(0, true);
        if (size < 0) throw new Error('tars: size invalid');
        const out = new Uint8Array(size);
        for (let i = 0; i < size; ++i) out[i] = this.readInt(0, true);
        return out;
      }
      throw new Error('tars: type mismatch');
    } else if (isRequire) {
      throw new Error('tars: require field not exist');
    }
    return new Uint8Array(0);
  }

  /** 读取元素为 string 的 List（readList<String>）。 */
  readStringList(tag: number, isRequire = false): string[] {
    const ls: string[] = [];
    if (this.skipToTag(tag)) {
      const hd = newHead();
      this.readHead(hd);
      if (hd.type !== TarsType.LIST) throw new Error('tars: type mismatch');
      const size = this.readInt(0, true);
      for (let i = 0; i < size; ++i) ls.push(this.readString(0, true));
    } else if (isRequire) {
      throw new Error('tars: require field not exist');
    }
    return ls;
  }

  /**
   * 读取嵌套结构字段：返回定位到结构体首字节的子流。
   * 与 Dart readTarsStruct 同构：读取后父流 skipToStructEnd 跳到 STRUCT_END 之后，
   * 子流内的字段读取不会影响父流位置。
   */
  readStruct(tag: number, isRequire = false): TarsInputStream {
    if (this.skipToTag(tag)) {
      const hd = newHead();
      this.readHead(hd);
      if (hd.type !== TarsType.STRUCT_BEGIN) throw new Error('tars: type mismatch');
      const sub = new TarsInputStream(this.bytes, this.position);
      this.skipToStructEnd();
      return sub;
    } else if (isRequire) {
      throw new Error('tars: require field not exist');
    }
    return new TarsInputStream(new Uint8Array(0));
  }

  /** 读取元素为结构的 List（readList<TarsStruct>），逐个回调子流。 */
  readStructList(tag: number, fn: (s: TarsInputStream) => void, isRequire = false): void {
    if (this.skipToTag(tag)) {
      const hd = newHead();
      this.readHead(hd);
      if (hd.type !== TarsType.LIST) throw new Error('tars: type mismatch');
      const size = this.readInt(0, true);
      for (let i = 0; i < size; ++i) {
        const eh = newHead();
        this.readHead(eh);
        if (eh.type !== TarsType.STRUCT_BEGIN) throw new Error('tars: type mismatch');
        fn(new TarsInputStream(this.bytes, this.position));
        this.skipToStructEnd();
      }
    } else if (isRequire) {
      throw new Error('tars: require field not exist');
    }
  }
}

class BinaryWriter {
  buffer: number[] = [];

  writeBytes(bytes: Uint8Array): void {
    for (const b of bytes) this.buffer.push(b);
  }

  writeInt(value: number, len: number): void {
    if (len === 1) {
      this.buffer.push(value & 0xff);
      return;
    }
    if (len === 2) {
      this.buffer.push((value >> 8) & 0xff, value & 0xff);
      return;
    }
    if (len === 4) {
      this.buffer.push(
        (value >>> 24) & 0xff,
        (value >>> 16) & 0xff,
        (value >>> 8) & 0xff,
        value & 0xff,
      );
      return;
    }
    if (len === 8) {
      const big = BigInt(Math.trunc(value));
      for (let i = 7; i >= 0; i--) {
        this.buffer.push(Number((big >> BigInt(i * 8)) & 0xffn));
      }
    }
  }
}

export class TarsOutputStream {
  private bw = new BinaryWriter();

  private writeHead(type: number, tag: number): void {
    if (tag < 15) {
      this.bw.writeInt((tag << 4) | type, 1);
    } else if (tag < 256) {
      this.bw.writeInt((15 << 4) | type, 1);
      this.bw.writeInt(tag, 1);
    } else {
      throw new Error(`tars: tag is too large: ${tag}`);
    }
  }

  /** 写入整数（自动选最小宽度，与 Dart writeInt 一致）。 */
  writeInt(n: number, tag: number): void {
    if (n >= -128 && n <= 127) {
      this.writeHead(n === 0 ? TarsType.ZERO_TAG : TarsType.BYTE, tag);
      if (n !== 0) this.bw.writeInt(n, 1);
      return;
    }
    if (n >= -32768 && n <= 32767) {
      this.writeHead(TarsType.SHORT, tag);
      this.bw.writeInt(n, 2);
      return;
    }
    if (n >= -2147483648 && n <= 2147483647) {
      this.writeHead(TarsType.INT, tag);
      this.bw.writeInt(n, 4);
      return;
    }
    this.writeHead(TarsType.LONG, tag);
    this.bw.writeInt(n, 8);
  }

  writeString(s: string, tag: number): void {
    const bytes = Buffer.from(s, 'utf8');
    if (bytes.length === 0) {
      this.writeHead(TarsType.STRING1, tag);
      this.bw.writeInt(0, 1);
      return;
    }
    if (bytes.length > 255) {
      this.writeHead(TarsType.STRING4, tag);
      this.bw.writeInt(bytes.length, 4);
      this.bw.writeBytes(bytes);
    } else {
      this.writeHead(TarsType.STRING1, tag);
      this.bw.writeInt(bytes.length, 1);
      this.bw.writeBytes(bytes);
    }
  }

  writeUint8List(ls: Uint8Array, tag: number): void {
    this.writeHead(TarsType.SIMPLE_LIST, tag);
    this.writeHead(TarsType.BYTE, 0);
    this.writeInt(ls.length, 0);
    this.bw.writeBytes(ls);
  }

  writeStringList(ls: string[], tag: number): void {
    this.writeHead(TarsType.LIST, tag);
    this.writeInt(ls.length, 0);
    for (const item of ls) this.writeString(item, 0);
  }

  toUint8Array(): Uint8Array {
    return Uint8Array.from(this.bw.buffer);
  }
}

// ---------------------------------------------------------------------------
// 虎牙命令帧与消息结构（huya_danmaku.dart 的 TarsStruct 子集）
// ---------------------------------------------------------------------------

/** 心跳：EWSCmdC2S_HeartBeatReq（20），当前网页心跳同款。 */
export function buildHuyaHeartbeat(): Uint8Array {
  const command = new TarsOutputStream();
  command.writeInt(20, 0);
  command.writeUint8List(new Uint8Array(0), 1);
  return command.toUint8Array();
}

/** 注册分组：EWSCmdC2S_RegisterGroupReq（16），组 live:{uid}/chat:{uid}。 */
export function buildHuyaRegisterGroup(uid: number): Uint8Array {
  const group = new TarsOutputStream();
  group.writeStringList([`live:${uid}`, `chat:${uid}`], 0);
  group.writeString('', 1);

  const command = new TarsOutputStream();
  command.writeInt(16, 0);
  command.writeUint8List(group.toUint8Array(), 1);
  return command.toUint8Array();
}

export interface HYMessageItem {
  uri: number;
  msg: Uint8Array;
  messageId: number;
}

/** 解析下行命令帧（type 7/22 展开 push 列表；type 4 为 WUP 响应，Node 侧不消费）。 */
export function decodeHuyaFrame(data: Uint8Array): {
  pushes: HYMessageItem[];
  wupData: Uint8Array | null;
  /** type=7 帧的附带字段（type 22 为 0）。 */
  pushType: number;
  protocolType: number;
} {
  const stream = new TarsInputStream(data);
  const type = stream.readInt(0, false);
  if (type === 7) {
    const inner = new TarsInputStream(stream.readBytes(1, false));
    // HYPushMessage{pushType=0, uri=1, msg=2, protocolType=3}
    const pushType = inner.readInt(0, false);
    const uri = inner.readInt(1, false);
    const msg = inner.readBytes(2, false);
    const protocolType = inner.readInt(3, false);
    return { pushes: [{ uri, msg, messageId: 0 }], wupData: null, pushType, protocolType };
  }
  if (type === 22) {
    // HYPushMessageV2{groupId=0, items=1 list<HYMessageItem{uri=0,msg=1,messageId=2}>}
    const inner = new TarsInputStream(stream.readBytes(1, false));
    const pushes: HYMessageItem[] = [];
    inner.readStructList(1, (itemStream) => {
      pushes.push({
        uri: itemStream.readInt(0, false),
        msg: itemStream.readBytes(1, false),
        messageId: itemStream.readInt(2, false),
      });
    });
    return { pushes, wupData: null, pushType: 0, protocolType: 0 };
  }
  if (type === 4) {
    return { pushes: [], wupData: stream.readBytes(1, false), pushType: 0, protocolType: 0 };
  }
  return { pushes: [], wupData: null, pushType: 0, protocolType: 0 };
}

export interface HYChatMessage {
  nickName: string;
  content: string;
  fontColor: number;
}

/** uri=1400 弹幕（HYMessage{userInfo=0(HYSender), content=3, bulletFormat=6}）。 */
export function decodeHuyaChat(payload: Uint8Array): HYChatMessage {
  const stream = new TarsInputStream(payload);
  let nickName = '';
  let fontColor = 0;
  try {
    // HYSender{uid=0, lMid=0, nickName=2, gender=3}
    const userInfo = stream.readStruct(0, false);
    nickName = userInfo.readString(2, false);
  } catch {
    nickName = '';
  }
  const content = stream.readString(3, false);
  try {
    // HYBulletFormat{fontColor=0, fontSize=1, textSpeed=2, transitionType=3}
    const bulletFormat = stream.readStruct(6, false);
    fontColor = bulletFormat.readInt(0, false);
  } catch {
    fontColor = 0;
  }
  return { nickName, content, fontColor };
}

/** uri=8006 人气（tag 0 整数）。 */
export function decodeHuyaAttendeeCount(payload: Uint8Array): number {
  return new TarsInputStream(payload).readInt(0, false);
}

export interface HuyaGiftMessage {
  iItemType: number;
  iItemCount: number;
  lSenderUid: number;
  sSenderNick: string;
  sPropsName: string;
  lPayTotal: number;
}

/** uri=6501 礼物（SendItemSubBroadcastPacket，字段逐个容错读取）。 */
export function decodeHuyaGift(payload: Uint8Array): HuyaGiftMessage {
  const stream = new TarsInputStream(payload);
  const gift: HuyaGiftMessage = {
    iItemType: 0,
    iItemCount: 1,
    lSenderUid: 0,
    sSenderNick: '',
    sPropsName: '',
    lPayTotal: 0,
  };
  const tryRead = (fn: () => void) => {
    try {
      fn();
    } catch {
      // 单字段缺失或类型不符时保留默认值
    }
  };
  tryRead(() => (gift.iItemType = stream.readInt(0, false)));
  tryRead(() => void stream.readString(1, false)); // strPayId
  tryRead(() => (gift.iItemCount = stream.readInt(2, false)));
  tryRead(() => void stream.readInt(3, false)); // lPresenterUid
  tryRead(() => (gift.lSenderUid = stream.readInt(4, false)));
  tryRead(() => void stream.readString(5, false)); // sPresenterNick
  tryRead(() => (gift.sSenderNick = stream.readString(6, false)));
  tryRead(() => void stream.readString(7, false)); // sSendContent
  tryRead(() => (gift.sPropsName = stream.readString(20, false)));
  tryRead(() => (gift.lPayTotal = stream.readInt(41, false)));
  return gift;
}

/** 弹幕颜色（fontColor int → #rrggbb；<=0 返回 undefined 表示白色默认）。 */
export function tarsColorToHex(fontColor: number): string | undefined {
  if (fontColor <= 0) return undefined;
  const rgb = fontColor & 0xffffff;
  return `#${rgb.toString(16).padStart(6, '0')}`;
}

export type { DanmakuMessageJson };
