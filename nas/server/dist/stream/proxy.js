"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.streamProxy = streamProxy;
const upstream_1 = require("../upstream");
/** 流媒体 CDN 的 Referer 校验白名单：命中才允许代理。 */
const PROXY_ALLOWED_HOST_SUFFIXES = [
    '.bilibili.com',
    '.hdslb.com',
    '.douyucdn.cn',
    '.douyucdn2.cn',
    '.huya.com',
    '.huyacdn.com',
    '.douyin.com',
    '.douyincdn.com',
    '.kuaishou.com',
    '.chenzhongtech.com',
];
async function streamProxy(target, reply) {
    let parsed;
    try {
        parsed = new URL(target);
    }
    catch {
        return reply.code(400).send({ error: 'invalid url' });
    }
    if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
        return reply.code(400).send({ error: 'invalid protocol' });
    }
    const hostOk = PROXY_ALLOWED_HOST_SUFFIXES.some((s) => parsed.hostname === s.slice(1) || parsed.hostname.endsWith(s));
    if (!hostOk)
        return reply.code(403).send({ error: 'host not allowed' });
    const headers = { referer: `${parsed.protocol}//${parsed.hostname}/`, origin: `${parsed.protocol}//${parsed.hostname}` };
    const range = reply.request.headers.range;
    if (typeof range === 'string')
        headers.range = range;
    try {
        const res = await (0, upstream_1.upstream)(target, { headers, timeoutMs: 30_000 });
        if (res.status >= 400)
            return reply.code(res.status).send({ error: `upstream ${res.status}` });
        reply.header('content-type', res.headers['content-type'] ?? 'application/octet-stream');
        if (res.headers['content-length'])
            reply.header('content-length', res.headers['content-length']);
        if (res.headers['accept-ranges'])
            reply.header('accept-ranges', res.headers['accept-ranges']);
        // 首版实现一次性回源到内存再转发；后续可改为流水线透传以降低延迟。
        reply.send(Buffer.from(res.text, 'binary'));
    }
    catch (err) {
        reply.code(502).send({ error: 'upstream failed' });
    }
}
