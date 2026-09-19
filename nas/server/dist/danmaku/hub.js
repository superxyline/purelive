"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.danmakuRoutes = void 0;
const sites_1 = require("../sites");
require("./connectors");
/**
 * 弹幕代理中心：前端连 GET /api/danmaku/:platform/:roomId（WebSocket 升级），
 * hub 为每个 platform:roomId 建立一个上游 Connector（负责与平台 wss 建连、
 * 认证、心跳、协议解析），多个前端客户端共享同一路上游连接。
 */
const registry_1 = require("./registry");
const sessions = new Map();
const danmakuRoutes = async (app) => {
    app.get('/:platform/:roomId', { websocket: true }, async (socket, req) => {
        const { platform, roomId } = req.params;
        const key = `${platform}:${roomId}`;
        try {
            let session = sessions.get(key);
            if (!session) {
                // 拉一次房间详情拿弹幕握手凭据（B站 token/serverUrls 等）
                let danmakuData = null;
                try {
                    const site = (0, sites_1.getSite)(platform);
                    const detail = await site.getRoomDetail(roomId);
                    danmakuData = detail.danmakuData ?? null;
                }
                catch (err) {
                    socket.send(JSON.stringify({ type: 'reload', message: `getRoomDetail failed: ${err}` }));
                    socket.close();
                    return;
                }
                const factory = (0, registry_1.getConnectorFactory)(platform);
                if (!factory) {
                    socket.send(JSON.stringify({ type: 'reload', message: `no connector for ${platform}` }));
                    socket.close();
                    return;
                }
                const connector = factory(roomId, danmakuData, (msg) => {
                    const s = sessions.get(key);
                    if (!s)
                        return;
                    const data = JSON.stringify(msg);
                    for (const client of s.clients) {
                        if (client.readyState === 1)
                            client.send(data);
                    }
                });
                session = { connector, clients: new Set([socket]) };
                sessions.set(key, session);
                connector.start().catch((err) => {
                    socket.send(JSON.stringify({ type: 'reload', message: `connector start failed: ${err}` }));
                });
            }
            else {
                session.clients.add(socket);
            }
            socket.on('message', () => {
                // 前端无需发送任何数据；保留通道以检测半开连接
            });
            socket.on('close', () => {
                const s = sessions.get(key);
                if (!s)
                    return;
                s.clients.delete(socket);
                if (s.clients.size === 0) {
                    s.connector.stop();
                    sessions.delete(key);
                }
            });
        }
        catch (err) {
            try {
                socket.send(JSON.stringify({ type: 'reload', message: `hub error: ${err}` }));
                socket.close();
            }
            catch (_) { }
        }
    });
};
exports.danmakuRoutes = danmakuRoutes;
