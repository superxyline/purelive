import type { LiveAnchorItemJson, LiveCategoryJson, LivePlayQualityJson, LiveRoomJson } from '../protocol';

/**
 * TS 版 LiveSite 接口（对应 lib/core/interface/live_site.dart），五平台各自实现。
 * cookie 通过 auth 模块托管（NAS 上的加密存储）。
 */
export interface Site {
  getCategories(page: number, pageSize: number): Promise<LiveCategoryJson[]>;
  getCategoryRooms(cateId: string, typeName: string, page: number, pageSize: number): Promise<LiveRoomJson[]>;
  getRecommendRooms(page: number, pageSize: number): Promise<LiveRoomJson[]>;
  searchRooms(keyword: string, page: number, pageSize: number): Promise<LiveRoomJson[]>;
  searchAnchors(keyword: string, page: number, pageSize: number): Promise<LiveAnchorItemJson[]>;
  getRoomDetail(roomId: string): Promise<LiveRoomJson>;
  getPlayQualites(roomId: string): Promise<LivePlayQualityJson[]>;
  /** codec: 首选编码（avc|hevc），仅 bilibili 使用，其余平台忽略。 */
  getPlayUrls(roomId: string, quality: string, codec?: string): Promise<string[]>;
  getLiveStatus(roomId: string): Promise<boolean>;
  sendDanmaku(roomId: string, message: string): Promise<[boolean, string]>;
}
