import type { FastifyPluginAsync } from 'fastify';

/** 登录与 cookie 托管（M5 实现：B站扫码 + 各平台粘贴 cookie，AES 加密落盘）。 */
export const authRoutes: FastifyPluginAsync = async (app) => {
  app.get('/status', async () => ({ platforms: {}, note: 'auth not implemented yet' }));
};
