import type { FastifyPluginAsync } from 'fastify';
import { streamProxy } from '../stream/proxy';

/** 流代理：直播流 CDN 校验 Referer/Origin 时，浏览器直连失败走这里回退。 */
export const streamRoutes: FastifyPluginAsync = async (app) => {
  app.get<{ Querystring: { url: string } }>('/proxy', async (req, reply) => {
    const target = req.query.url;
    if (!target) return reply.code(400).send({ error: 'missing url' });
    return streamProxy(target, reply);
  });
};
