import type { FastifyPluginAsync } from 'fastify';
import { connect } from 'node:net';
import { PLATFORMS } from '../protocol';
import { getSite } from '../sites';

/** TCP 握手测速：连接 host:443 计时，失败/超时记 9999（对齐安卓 CdnSpeedTest 语义）。 */
function probeHost(host: string): Promise<number> {
  return new Promise((resolve) => {
    const start = Date.now();
    const sock = connect({ host, port: 443 });
    const done = (ms: number) => {
      sock.removeAllListeners();
      sock.destroy();
      resolve(ms);
    };
    sock.setTimeout(1500, () => done(9999));
    sock.once('connect', () => done(Date.now() - start));
    sock.once('error', () => done(9999));
  });
}

export const siteRoutes: FastifyPluginAsync = async (app) => {
  app.get('/sites', async () => {
    return PLATFORMS.map((p) => ({ id: p, name: p }));
  });

  app.get<{ Params: { p: string }; Querystring: { page?: string; size?: string } }>(
    '/sites/:p/categories',
    async (req) => {
      const site = getSite(req.params.p);
      return { data: await site.getCategories(Number(req.query.page ?? 1), Number(req.query.size ?? 20)) };
    },
  );

  app.get<{ Params: { p: string; cateId: string }; Querystring: { page?: string; size?: string; typeName?: string } }>(
    '/sites/:p/categories/:cateId/rooms',
    async (req) => {
      const site = getSite(req.params.p);
      const { cateId } = req.params;
      const typeName = req.query.typeName ?? '';
      return {
        data: await site.getCategoryRooms(cateId, typeName, Number(req.query.page ?? 1), Number(req.query.size ?? 20)),
      };
    },
  );

  app.get<{ Params: { p: string }; Querystring: { page?: string; size?: string } }>(
    '/sites/:p/recommend',
    async (req) => {
      const site = getSite(req.params.p);
      return { data: await site.getRecommendRooms(Number(req.query.page ?? 1), Number(req.query.size ?? 20)) };
    },
  );

  app.get<{ Params: { p: string }; Querystring: { q: string; page?: string; size?: string; anchors?: string } }>(
    '/sites/:p/search',
    async (req) => {
      const site = getSite(req.params.p);
      const anchors = req.query.anchors === 'true';
      const data = anchors
        ? await site.searchAnchors(req.query.q, Number(req.query.page ?? 1), Number(req.query.size ?? 20))
        : await site.searchRooms(req.query.q, Number(req.query.page ?? 1), Number(req.query.size ?? 20));
      return { data };
    },
  );

  app.get<{ Params: { p: string; roomId: string } }>('/sites/:p/rooms/:roomId', async (req) => {
    const site = getSite(req.params.p);
    return { data: await site.getRoomDetail(req.params.roomId) };
  });

  app.get<{ Params: { p: string; roomId: string }; Querystring: { quality?: string; codec?: string } }>(
    '/sites/:p/rooms/:roomId/play-urls',
    async (req) => {
      const site = getSite(req.params.p);
      const quality = req.query.quality ?? '';
      const codec = req.query.codec === 'hevc' ? 'hevc' : 'avc';
      // 不带 quality 的调用是前端在取清晰度列表，此时不能解析播放地址
      //（各平台 getPlayUrls 都要求有效清晰度，空值会抛错导致列表也拿不到）。
      const urls = quality ? await site.getPlayUrls(req.params.roomId, quality, codec) : [];
      return {
        qualities: await site.getPlayQualites(req.params.roomId),
        urls,
      };
    },
  );

  // CDN 线路 TCP 握手测速（静态路径需先于 :p 参数路由注册，fastify 静态优先但显式排前更稳）
  app.get<{ Querystring: { hosts?: string } }>('/sites/speedtest', async (req) => {
    const hosts = String(req.query.hosts ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
      .slice(0, 16)
      .filter((h) => h.length <= 253 && /^[a-zA-Z0-9.\-:]+$/.test(h));
    const results = await Promise.all(hosts.map(async (h) => [h, await probeHost(h)] as const));
    return { data: Object.fromEntries(results) };
  });

  app.get<{ Params: { p: string; roomId: string } }>('/sites/:p/rooms/:roomId/live-status', async (req) => {
    const site = getSite(req.params.p);
    return { live: await site.getLiveStatus(req.params.roomId) };
  });

  app.post<{ Params: { p: string }; Body: { roomId: string; message: string } }>(
    '/sites/:p/danmaku/send',
    async (req, reply) => {
      const site = getSite(req.params.p);
      const [ok, msg] = await site.sendDanmaku(req.body.roomId, req.body.message);
      return reply.code(ok ? 200 : 400).send({ ok, message: msg });
    },
  );
};
