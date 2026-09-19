import type { FastifyPluginAsync } from 'fastify';
import { evalDouyuSign } from '../sign/douyu';
import { evalDouyinAbogus, evalDouyinSignature, evalDouyinMsStub } from '../sign/douyin';

/** 签名端点：Flutter Web 端无 QuickJS，斗鱼/抖音取流签名在这里执行原 JS 片段。 */
export const signRoutes: FastifyPluginAsync = async (app) => {
  app.post<{ Body: { html: string; rid: string } }>('/douyu', async (req) => {
    return { sign: evalDouyuSign(req.body.html, req.body.rid) };
  });

  app.post<{ Body: { url: string; userAgent: string } }>('/douyin/abogus', async (req) => {
    return { result: evalDouyinAbogus(req.body.url, req.body.userAgent) };
  });

  app.post<{ Body: { roomId: string; uniqueId: string } }>('/douyin/signature', async (req) => {
    return { result: evalDouyinSignature(req.body.roomId, req.body.uniqueId) };
  });

  app.post<{ Body: { roomId: string; uniqueId: string } }>('/douyin/msStub', async (req) => {
    return { result: evalDouyinMsStub(req.body.roomId, req.body.uniqueId) };
  });
};
