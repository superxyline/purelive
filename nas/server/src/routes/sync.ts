import fs from 'node:fs';
import path from 'node:path';
import type { FastifyPluginAsync } from 'fastify';
import { setStoredCookie } from '../auth/store';

/**
 * 手机 App 扫码同步：App 内「跨端传输」扫码后，会把本机关注+登录+全部设置
 * POST 到 <二维码地址>/api/importData（body 为 exportTransferData 的 JSON），
 * 并以响应体 {data: true} 作为成功标志。这里接收并提取关注列表供 WebUI 导入。
 */

const DATA_DIR = process.env.PURE_LIVE_DATA_DIR || path.join(process.cwd(), '..', 'data');
const SYNC_FILE = path.join(DATA_DIR, 'synced-follows.json');

interface SyncedFollow {
  platform: string;
  roomId: string;
  nick: string;
  title: string;
  cover: string;
}

function readSynced(): { syncedAt: number; list: SyncedFollow[] } {
  try {
    return JSON.parse(fs.readFileSync(SYNC_FILE, 'utf8'));
  } catch (_) {
    return { syncedAt: 0, list: [] };
  }
}

function writeSynced(list: SyncedFollow[]): void {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(SYNC_FILE, JSON.stringify({ syncedAt: Date.now(), list }));
}

/** 任意来源的原始列表 → synced-follows 格式（去重+平台校验） */
function extractList(rawList: unknown): SyncedFollow[] {
  if (!Array.isArray(rawList)) return [];
  const seen = new Set<string>();
  const out: SyncedFollow[] = [];
  for (const r of rawList) {
    const platform = String(r?.platform ?? '').toLowerCase();
    const roomId = String(r?.roomId ?? '');
    if (!platform || !roomId || !['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'].includes(platform)) continue;
    const key = `${platform}:${roomId}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({
      platform,
      roomId,
      nick: String(r?.nick ?? ''),
      title: String(r?.title ?? ''),
      cover: String(r?.cover ?? ''),
    });
  }
  return out;
}

/** App 的 exportTransferData → WebUI 关注列表格式 */
function extractFollows(body: any): SyncedFollow[] {
  // App 端 FavoriteRoomController.toJson() 的键是 favoriteRooms；早期方案/手工请求可能用 list，两者都认。
  return extractList(body?.favorite?.favoriteRooms ?? body?.favorite?.list);
}

export const syncRoutes: FastifyPluginAsync = async (app) => {
  // 手机 App 扫码推送的接收端点（App 校验响应体 {data: true}）
  app.post('/importData', async (req, reply) => {
    try {
      const list = extractFollows(req.body);
      writeSynced(list);
      // 同步各平台登录态（cookie）到托管存储：此后各平台 API 请求自动带登录态
      //（App 推送的 exportTransferData 里 cookie 字段为 {bilibiliCookie: "...", ...}）
      const cookie = (req.body as any)?.cookie;
      let cookieCount = 0;
      if (cookie && typeof cookie === 'object') {
        for (const p of ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou']) {
          const v = cookie[`${p}Cookie`];
          if (typeof v === 'string' && v.trim()) {
            setStoredCookie(p, v.trim());
            cookieCount++;
          }
        }
      }
      app.log.info(`[sync] imported ${list.length} follows, ${cookieCount} cookies from mobile app`);
      return { data: true };
    } catch (err) {
      app.log.error(err);
      return reply.code(400).send({ data: false });
    }
  });

  // WebUI 拉取已同步的关注列表
  app.get('/sync/follows', async () => {
    const { syncedAt, list } = readSynced();
    return { syncedAt, list };
  });

  // 同步状态（页面上提示用）
  app.get('/sync/status', async () => {
    const { syncedAt, list } = readSynced();
    return { syncedAt, count: list.length };
  });

  // WebUI 关注列表写穿 / 安卓端推送：浏览器与 App 均覆盖持久化到 NAS（多设备共享/换设备恢复）
  const saveFollows = async (req: { body?: { list?: unknown } }) => {
    const list = extractList((req.body as any)?.list);
    writeSynced(list);
    return { ok: true, count: list.length };
  };
  app.put<{ Body: { list?: unknown } }>('/sync/follows', saveFollows);
  // App 的 HttpClient 只有 postJson，POST 同语义兼容
  app.post<{ Body: { list?: unknown } }>('/sync/follows', saveFollows);
};
