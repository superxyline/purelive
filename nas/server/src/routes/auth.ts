import type { FastifyPluginAsync } from 'fastify';
import { upstream } from '../upstream';
import { getStoredCookie, setStoredCookie, allPlatformsStatus } from './store';

/** 登录与 cookie 托管：B站扫码（后端代理 passport 接口）+ 各平台粘贴 cookie。 */
export const authRoutes: FastifyPluginAsync = async (app) => {
  app.get('/status', async () => {
    return {
      platforms: allPlatformsStatus(['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou']),
    };
  });

  // ---- B站扫码登录 ----
  app.get('/bilibili/qrcode', async () => {
    const res = await upstream(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
      { headers: { origin: 'https://passport.bilibili.com', referer: 'https://passport.bilibili.com/' } },
    );
    return JSON.parse(res.text);
  });

  app.get<{ Querystring: { qrcode_key: string } }>('/bilibili/qrcode/poll', async (req) => {
    const key = req.query.qrcode_key;
    if (!key) return { code: -400, message: 'missing qrcode_key' };
    const res = await upstream(
      `https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=${encodeURIComponent(key)}`,
      {
        headers: { origin: 'https://passport.bilibili.com', referer: 'https://passport.bilibili.com/' },
        redirect: 'manual',
      },
    );
    // 登录成功时 Set-Cookie 里携带 SESSDATA/bili_jct/DedeUserID 等，拼成完整 cookie 串托管
    if (res.setCookies.length > 0) {
      const pairs = res.setCookies
        .map((c) => c.split(';')[0])
        .filter((p) => p.includes('='));
      if (pairs.length > 0) {
        const existing = getStoredCookie('bilibili');
        const merged = mergeCookies(existing, pairs.join('; '));
        setStoredCookie('bilibili', merged);
      }
    }
    return JSON.parse(res.text);
  });

  // ---- 各平台粘贴 cookie ----
  app.get<{ Params: { platform: string } }>('/:platform', async (req) => {
    const { platform } = req.params;
    if (!['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'].includes(platform)) {
      return { code: -400, message: 'unknown platform' };
    }
    const cookie = getStoredCookie(platform);
    return { platform, hasCookie: cookie.length > 0, cookiePreview: cookie.slice(0, 24) };
  });

  app.post<{ Params: { platform: string }; Body: { cookie: string } }>('/:platform', async (req, reply) => {
    const { platform } = req.params;
    if (!['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'].includes(platform)) {
      return reply.code(400).send({ ok: false, message: 'unknown platform' });
    }
    setStoredCookie(platform, (req.body?.cookie ?? '').trim());
    return { ok: true };
  });

  app.delete<{ Params: { platform: string } }>('/:platform', async (req) => {
    setStoredCookie(req.params.platform, '');
    return { ok: true };
  });
};

/** 合并新旧 cookie：新值覆盖同名字段，保留旧值里仍有效的字段。 */
function mergeCookies(oldCookie: string, newCookie: string): string {
  const map = new Map<string, string>();
  for (const part of `${oldCookie};${newCookie}`.split(';')) {
    const idx = part.indexOf('=');
    if (idx <= 0) continue;
    const k = part.slice(0, idx).trim();
    const v = part.slice(idx + 1).trim();
    if (k && v) map.set(k, v);
  }
  return [...map.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
}
