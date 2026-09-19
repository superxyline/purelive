import fs from 'node:fs';
import path from 'node:path';
import type { FastifyPluginAsync } from 'fastify';

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

/** App 的 exportTransferData → WebUI 关注列表格式（去重） */
function extractFollows(body: any): SyncedFollow[] {
  const rawList = body?.favorite?.list;
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

export const syncRoutes: FastifyPluginAsync = async (app) => {
  // 手机 App 扫码推送的接收端点（App 校验响应体 {data: true}）
  app.post('/importData', async (req, reply) => {
    try {
      const list = extractFollows(req.body);
      writeSynced(list);
      app.log.info(`[sync] imported ${list.length} follows from mobile app`);
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
};
