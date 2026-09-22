"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.siteRoutes = void 0;
const protocol_1 = require("../protocol");
const sites_1 = require("../sites");
const siteRoutes = async (app) => {
    app.get('/sites', async () => {
        return protocol_1.PLATFORMS.map((p) => ({ id: p, name: p }));
    });
    app.get('/sites/:p/categories', async (req) => {
        const site = (0, sites_1.getSite)(req.params.p);
        return { data: await site.getCategories(Number(req.query.page ?? 1), Number(req.query.size ?? 20)) };
    });
    app.get('/sites/:p/categories/:cateId/rooms', async (req) => {
        const site = (0, sites_1.getSite)(req.params.p);
        const { cateId } = req.params;
        const typeName = req.query.typeName ?? '';
        return {
            data: await site.getCategoryRooms(cateId, typeName, Number(req.query.page ?? 1), Number(req.query.size ?? 20)),
        };
    });
    app.get('/sites/:p/recommend', async (req) => {
        const site = (0, sites_1.getSite)(req.params.p);
        return { data: await site.getRecommendRooms(Number(req.query.page ?? 1), Number(req.query.size ?? 20)) };
    });
    app.get('/sites/:p/search', async (req) => {
        const site = (0, sites_1.getSite)(req.params.p);
        const anchors = req.query.anchors === 'true';
        const data = anchors
            ? await site.searchAnchors(req.query.q, Number(req.query.page ?? 1), Number(req.query.size ?? 20))
            : await site.searchRooms(req.query.q, Number(req.query.page ?? 1), Number(req.query.size ?? 20));
        return { data };
    });
    app.get('/sites/:p/rooms/:roomId', async (req) => {
        const site = (0, sites_1.getSite)(req.params.p);
        return { data: await site.getRoomDetail(req.params.roomId) };
    });
    app.get('/sites/:p/rooms/:roomId/play-urls', async (req) => {
        const site = (0, sites_1.getSite)(req.params.p);
        const quality = req.query.quality ?? '';
        // 不带 quality 的调用是前端在取清晰度列表，此时不能解析播放地址
        //（各平台 getPlayUrls 都要求有效清晰度，空值会抛错导致列表也拿不到）。
        const urls = quality ? await site.getPlayUrls(req.params.roomId, quality) : [];
        return {
            qualities: await site.getPlayQualites(req.params.roomId),
            urls,
        };
    });
    app.get('/sites/:p/rooms/:roomId/live-status', async (req) => {
        const site = (0, sites_1.getSite)(req.params.p);
        return { live: await site.getLiveStatus(req.params.roomId) };
    });
    app.post('/sites/:p/danmaku/send', async (req, reply) => {
        const site = (0, sites_1.getSite)(req.params.p);
        const [ok, msg] = await site.sendDanmaku(req.body.roomId, req.body.message);
        return reply.code(ok ? 200 : 400).send({ ok, message: msg });
    });
};
exports.siteRoutes = siteRoutes;
