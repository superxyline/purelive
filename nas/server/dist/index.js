"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const fastify_1 = __importDefault(require("fastify"));
const cors_1 = __importDefault(require("@fastify/cors"));
const websocket_1 = __importDefault(require("@fastify/websocket"));
const sites_1 = require("./routes/sites");
const sign_1 = require("./routes/sign");
const auth_1 = require("./routes/auth");
const stream_1 = require("./routes/stream");
const hub_1 = require("./danmaku/hub");
const PORT = Number(process.env.PORT || 8080);
const app = (0, fastify_1.default)({
    logger: {
        level: process.env.LOG_LEVEL || 'info',
    },
});
async function main() {
    await app.register(cors_1.default, { origin: true, credentials: true });
    await app.register(websocket_1.default, { options: { maxPayload: 4 * 1024 * 1024 } });
    await app.register(sites_1.siteRoutes, { prefix: '/api' });
    await app.register(sign_1.signRoutes, { prefix: '/api/sign' });
    await app.register(auth_1.authRoutes, { prefix: '/api/auth' });
    await app.register(stream_1.streamRoutes, { prefix: '/api/stream' });
    await app.register(hub_1.danmakuRoutes, { prefix: '/api/danmaku' });
    app.get('/api/health', async () => ({ ok: true, ts: Date.now() }));
    await app.listen({ port: PORT, host: '0.0.0.0' });
}
main().catch((err) => {
    app.log.error(err);
    process.exit(1);
});
