import fs from 'node:fs';
import path from 'node:path';
import Fastify from 'fastify';
import cors from '@fastify/cors';
import websocket from '@fastify/websocket';
import { siteRoutes } from './routes/sites';
import { signRoutes } from './routes/sign';
import { authRoutes } from './routes/auth';
import { streamRoutes } from './routes/stream';
import { syncRoutes } from './routes/sync';
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

  // 可选访问令牌：设置 PURE_LIVE_TOKEN 后，所有 /api/*（除 /api/health）要求
  // 请求头 x-api-token 或查询参数 token 匹配——供公网（云服务器）部署做最小
  // 访问控制（保护托管的平台登录 Cookie 与关注数据）。不设置则与原行为一致，
  // 适用于 NAS 局域网 / 电脑便携版等可信网络。
  const apiToken = process.env.PURE_LIVE_TOKEN || '';
  if (apiToken) {
    app.addHook('onRequest', async (req, reply) => {
      const url = req.raw.url || '';
      if (!url.startsWith('/api/') || url.startsWith('/api/health')) return;
      const provided = (req.headers['x-api-token'] as string) || '';
      const qIndex = url.indexOf('token=');
      const queryToken = qIndex >= 0
        ? decodeURIComponent(url.slice(qIndex + 6).split('&')[0])
        : '';
      if (provided === apiToken || queryToken === apiToken) return;
      reply.code(401).send({ error: 'unauthorized: missing or invalid token' });
    });
    app.log.info('API access token protection enabled');
  }

  await app.register(siteRoutes, { prefix: '/api' });
  await app.register(signRoutes, { prefix: '/api/sign' });
  await app.register(authRoutes, { prefix: '/api/auth' });
  await app.register(streamRoutes, { prefix: '/api/stream' });
  await app.register(syncRoutes, { prefix: '/api' });
  await app.register(danmakuRoutes, { prefix: '/api/danmaku' });

  app.get('/api/health', async () => ({ ok: true, ts: Date.now() }));

  // 便携部署（无 NAS，Windows 电脑直接跑）：设置 PURE_LIVE_WEBUI_DIR 后由
  // server 自托管 WebUI 静态文件，替代 nginx 的静态托管 + /api 反代 + SPA 回退。
  // NAS 部署不受影响（不设该变量时行为与原来完全一致）。
  const webuiDir = process.env.PURE_LIVE_WEBUI_DIR || '';
  if (webuiDir) {
    const MIME: Record<string, string> = {
      '.html': 'text/html; charset=utf-8',
      '.js': 'application/javascript; charset=utf-8',
      '.mjs': 'application/javascript; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.json': 'application/json; charset=utf-8',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.gif': 'image/gif',
      '.svg': 'image/svg+xml',
      '.ico': 'image/x-icon',
      '.woff': 'font/woff',
      '.woff2': 'font/woff2',
      '.ttf': 'font/ttf',
      '.wasm': 'application/wasm',
      '.map': 'application/json',
      '.txt': 'text/plain; charset=utf-8',
    };
    const webuiRoot = path.resolve(webuiDir);
    app.setNotFoundHandler((req, reply) => {
      const urlPath = decodeURIComponent((req.raw.url || '/').split('?')[0]);
      if (urlPath.startsWith('/api/')) {
        reply.code(404).send({ error: 'not found' });
        return;
      }
      // 防路径穿越：规范化后必须仍在 webui 根目录内
      const rel = path.normalize(urlPath).replace(/^([.][.][\\/])+/, '');
      let file = path.join(webuiRoot, rel === '.' || rel === '\\' ? 'index.html' : rel);
      if (!path.resolve(file).startsWith(webuiRoot)) {
        reply.code(403).send();
        return;
      }
      if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        file = path.join(webuiRoot, 'index.html'); // SPA 路由回退
      }
      if (!fs.existsSync(file)) {
        reply.code(404).send('webui files missing');
        return;
      }
      const ext = path.extname(file).toLowerCase();
      reply.header('content-type', MIME[ext] || 'application/octet-stream');
      reply.header(
        'cache-control',
        ext === '.html' ? 'no-cache' : 'public, max-age=604800',
      );
      reply.send(fs.readFileSync(file));
    });
    app.log.info(`portable webui served from ${webuiRoot}`);
  }

  await app.listen({ port: PORT, host: '0.0.0.0' });
}

main().catch((err) => {
  app.log.error(err);
  process.exit(1);
});
