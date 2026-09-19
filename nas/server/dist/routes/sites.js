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
        return {
            qualities: await site.getPlayQualites(req.params.roomId),
            urls: await site.getPlayUrls(req.params.roomId, req.query.quality ?? ''),
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
