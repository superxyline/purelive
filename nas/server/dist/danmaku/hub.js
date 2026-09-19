"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.danmakuRoutes = void 0;
/**
 * 弹幕代理中心（M3 实现）：
 * GET /api/danmaku/:platform/:roomId → WebSocket 升级，
 * 后端与平台 wss 建连（注入 UA/Origin/Referer/cookie）、发认证包、心跳、
 * 协议解析为统一 DanmakuMessageJson 推给前端。
 */
const danmakuRoutes = async (app) => {
    app.get('/:platform/:roomId', { websocket: true }, (socket, req) => {
        socket.send(JSON.stringify({ type: 'reload', message: 'danmaku hub: not implemented yet (M3)' }));
        socket.close();
    });
};
exports.danmakuRoutes = danmakuRoutes;
