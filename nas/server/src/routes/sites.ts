import type { FastifyPluginAsync } from 'fastify';
import { PLATFORMS } from '../protocol';
import { getSite } from '../sites';

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

  app.get<{ Params: { p: string; roomId: string }; Querystring: { quality: string } }>(
    '/sites/:p/rooms/:roomId/play-urls',
    async (req) => {
      const site = getSite(req.params.p);
      const quality = req.query.quality ?? '';
      // 不带 quality 的调用是前端在取清晰度列表，此时不能解析播放地址
      //（各平台 getPlayUrls 都要求有效清晰度，空值会抛错导致列表也拿不到）。
      const urls = quality ? await site.getPlayUrls(req.params.roomId, quality) : [];
      return {
        qualities: await site.getPlayQualites(req.params.roomId),
        urls,
      };
    },
  );

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
