"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.authRoutes = void 0;
const upstream_1 = require("../upstream");
const store_1 = require("../auth/store");
const cookies_1 = require("../auth/cookies");
/** 登录与 cookie 托管：B站扫码（后端代理 passport 接口）+ 各平台粘贴 cookie。 */
const authRoutes = async (app) => {
    app.get('/status', async () => {
        return {
            platforms: (0, store_1.allPlatformsStatus)(['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou']),
        };
    });
    // ---- B站扫码登录 ----
    app.get('/bilibili/qrcode', async () => {
        const res = await (0, upstream_1.upstream)('https://passport.bilibili.com/x/passport-login/web/qrcode/generate', { headers: { origin: 'https://passport.bilibili.com', referer: 'https://passport.bilibili.com/' } });
        return JSON.parse(res.text);
    });
    app.get('/bilibili/qrcode/poll', async (req) => {
        const key = req.query.qrcode_key;
        if (!key)
            return { code: -400, message: 'missing qrcode_key' };
        const res = await (0, upstream_1.upstream)(`https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=${encodeURIComponent(key)}`, {
            headers: { origin: 'https://passport.bilibili.com', referer: 'https://passport.bilibili.com/' },
            redirect: 'manual',
        });
        // 登录成功时 Set-Cookie 里携带 SESSDATA/bili_jct/DedeUserID 等，拼成完整 cookie 串托管
        if (res.setCookies.length > 0) {
            const pairs = res.setCookies
                .map((c) => c.split(';')[0])
                .filter((p) => p.includes('='));
            if (pairs.length > 0) {
                const existing = (0, store_1.getStoredCookie)('bilibili');
                const merged = mergeCookies(existing, pairs.join('; '));
                (0, store_1.setStoredCookie)('bilibili', merged);
                // 同步进程内缓存，否则本次运行内 getCookie 仍返回旧值（重启前不生效）
                (0, cookies_1.setCookie)('bilibili', merged);
            }
        }
        return JSON.parse(res.text);
    });
    // ---- 各平台粘贴 cookie ----
    // B站会话信息：用托管 cookie 代理账号信息接口，供 Web 端展示登录态
    app.get('/bilibili/session', async () => {
        const cookie = (0, store_1.getStoredCookie)('bilibili') || (0, cookies_1.getCookie)('bilibili');
        if (!cookie)
            return { ok: false, uname: '', mid: 0 };
        try {
            const res = await (0, upstream_1.upstream)('https://api.bilibili.com/x/member/web/account', {
                headers: { cookie, referer: 'https://www.bilibili.com/' },
            });
            const body = JSON.parse(res.text);
            if (body['code'] !== 0)
                return { ok: false, uname: '', mid: 0 };
            return { ok: true, uname: String(body['data']?.uname ?? ''), mid: Number(body['data']?.mid ?? 0) };
        }
        catch (_) {
            return { ok: false, uname: '', mid: 0 };
        }
    });
    app.get('/:platform', async (req) => {
        const { platform } = req.params;
        if (!['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'].includes(platform)) {
            return { code: -400, message: 'unknown platform' };
        }
        const cookie = (0, store_1.getStoredCookie)(platform);
        return { platform, hasCookie: cookie.length > 0, cookiePreview: cookie.slice(0, 24) };
    });
    app.post('/:platform', async (req, reply) => {
        const { platform } = req.params;
        if (!['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'].includes(platform)) {
            return reply.code(400).send({ ok: false, message: 'unknown platform' });
        }
        // 粘贴的 cookie 常带换行/制表符，先归一化再落盘，否则拼请求头时会整条失效
        const value = (req.body?.cookie ?? '').replace(/[\r\n\t]+/g, '').trim();
        (0, store_1.setStoredCookie)(platform, value);
        // 同步进程内缓存：不刷新的话，本次运行期间各 site 仍会读到旧 cookie（需重启容器才生效）
        (0, cookies_1.setCookie)(platform, value);
        return { ok: true };
    });
    app.delete('/:platform', async (req, reply) => {
        const { platform } = req.params;
        if (!['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'].includes(platform)) {
            return reply.code(400).send({ ok: false, message: 'unknown platform' });
        }
        (0, store_1.setStoredCookie)(platform, '');
        (0, cookies_1.setCookie)(platform, '');
        return { ok: true };
    });
};
exports.authRoutes = authRoutes;
/** 合并新旧 cookie：新值覆盖同名字段，保留旧值里仍有效的字段。 */
function mergeCookies(oldCookie, newCookie) {
    const map = new Map();
    for (const part of `${oldCookie};${newCookie}`.split(';')) {
        const idx = part.indexOf('=');
        if (idx <= 0)
            continue;
        const k = part.slice(0, idx).trim();
        const v = part.slice(idx + 1).trim();
        if (k && v)
            map.set(k, v);
    }
    return [...map.entries()].map(([k, v]) => `${k}=${v}`).join('; ');
}
