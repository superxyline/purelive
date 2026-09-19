import Fastify from 'fastify';
import cors from '@fastify/cors';
import websocket from '@fastify/websocket';
import { siteRoutes } from './routes/sites';
import { signRoutes } from './routes/sign';
import { authRoutes } from './routes/auth';
import { streamRoutes } from './routes/stream';
import { danmakuRoutes } from './danmaku/hub';

const PORT = Number(process.env.PORT || 8080);

const app = Fastify({
  logger: {
    level: process.env.LOG_LEVEL || 'info',
  },
});

async function main() {
  await app.register(cors, { origin: true, credentials: true });
  await app.register(websocket, { options: { maxPayload: 4 * 1024 * 1024 } });

  await app.register(siteRoutes, { prefix: '/api' });
  await app.register(signRoutes, { prefix: '/api/sign' });
  await app.register(authRoutes, { prefix: '/api/auth' });
  await app.register(streamRoutes, { prefix: '/api/stream' });
  await app.register(danmakuRoutes, { prefix: '/api/danmaku' });

  app.get('/api/health', async () => ({ ok: true, ts: Date.now() }));

  await app.listen({ port: PORT, host: '0.0.0.0' });
}

main().catch((err) => {
  app.log.error(err);
  process.exit(1);
});
