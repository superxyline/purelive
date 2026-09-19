/**
 * 与 Flutter 端数据模型逐字段对齐的 JSON 协议。
 * 参考 lib/common/models/live_room.dart (fromJson) 与 lib/model/live_category.dart 等。
 */

export type Platform = 'bilibili' | 'douyu' | 'huya' | 'douyin' | 'kuaishou';

export const PLATFORMS: Platform[] = ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'];

/** LiveStatus 枚举 index：live=0, offline=1, replay=2, unknown=3, banned=4 */
export const LiveStatus = { live: 0, offline: 1, replay: 2, unknown: 3, banned: 4 } as const;

/** AudienceMetricType 枚举 name（前端按 name 匹配） */
export type AudienceMetricType = 'popularity' | 'onlineViewers' | 'totalViewers' | 'followers' | 'unknown';

export interface LiveRoomJson {
  roomId: string;
  userId: string;
  link: string;
  title: string;
  nick: string;
  avatar: string;
  cover: string;
  area: string;
  watching: string;
  audienceMetricType?: AudienceMetricType;
  popularity: string;
  onlineViewers: string;
  totalViewers: string;
  followers: string;
  platform: string;
  tagIds?: string[];
  liveStatus: number;
  status: boolean;
  notice: string;
  introduction: string;
  isRecord: boolean;
  /** 平台私有播放解析数据（douyu 签名串 / huya antiCode / douyin stream_url / kuaishou playUrls），原样透传 */
  data?: unknown;
  /** 弹幕握手凭据（bilibili: token/serverUrls/buvid；huya: uid/topSid/subSid；douyin: webRid/userId） */
  danmakuData?: unknown;
  epgId: string;
  currentProgramme: string;
  currentProgrammeDescription: string;
  liveStartTime?: number | null;
}

export function emptyRoom(platform: string, roomId: string): LiveRoomJson {
  return {
    roomId,
    userId: '',
    link: '',
    title: '',
    nick: '',
    avatar: '',
    cover: '',
    area: '',
    watching: '0',
    popularity: '',
    onlineViewers: '',
    totalViewers: '',
    followers: '0',
    platform,
    liveStatus: LiveStatus.unknown,
    status: false,
    notice: '',
    introduction: '',
    isRecord: false,
    epgId: '',
    currentProgramme: '',
    currentProgrammeDescription: '',
  };
}

export interface LiveAreaJson {
  platform: string;
  areaType: string;
  typeName: string;
  areaId: string;
  areaName: string;
  areaPic: string;
  shortName: string;
}

export interface LiveCategoryJson {
  name: string;
  id: string;
  children: LiveAreaJson[];
}

export interface LivePlayQualityJson {
  quality: string;
  /** 平台私有清晰度数据（bilibili: {baseUrl, codecs, ...}；douyu: {rate}；huya: {iBitRate,...}），原样透传 */
  data?: unknown;
  sort: number;
}

export interface LiveAnchorItemJson {
  roomId: string;
  title: string;
  nick: string;
  avatar: string;
  cover: string;
  platform: string;
  liveStatus: number;
  followers?: string;
}

/**
 * 弹幕统一消息（前端 LiveMessage 对齐）。
 * type: msg=弹幕 | gift=礼物 | online=人气 | sc=醒目留言 | reload=重连提示
 */
export interface DanmakuMessageJson {
  type: 'msg' | 'gift' | 'online' | 'sc' | 'reload';
  userName?: string;
  message?: string;
  face?: string;
  giftName?: string;
  giftPrice?: number;
  giftCount?: number;
  giftColor?: string;
  totalCoin?: number;
  onlineCount?: number;
  subMessage?: string;
}
