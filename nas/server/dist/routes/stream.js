"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.streamRoutes = void 0;
const proxy_1 = require("../stream/proxy");
/** 流代理：直播流 CDN 校验 Referer/Origin 时，浏览器直连失败走这里回退。 */
const streamRoutes = async (app) => {
    app.get('/proxy', async (req, reply) => {
        const target = req.query.url;
        if (!target)
            return reply.code(400).send({ error: 'missing url' });
        return (0, proxy_1.streamProxy)(target, reply);
    });
};
exports.streamRoutes = streamRoutes;
