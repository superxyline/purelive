import type { FastifyPluginAsync } from 'fastify';

/**
 * 弹幕代理中心（M3 实现）：
 * GET /api/danmaku/:platform/:roomId → WebSocket 升级，
 * 后端与平台 wss 建连（注入 UA/Origin/Referer/cookie）、发认证包、心跳、
 * 协议解析为统一 DanmakuMessageJson 推给前端。
 */
export const danmakuRoutes: FastifyPluginAsync = async (app) => {
  app.get<{ Params: { platform: string; roomId: string } }>('/:platform/:roomId', { websocket: true }, (socket, req) => {
    socket.send(JSON.stringify({ type: 'reload', message: 'danmaku hub: not implemented yet (M3)' }));
    socket.close();
  });
};
