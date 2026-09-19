import { Readable } from 'node:stream';
import type { FastifyReply } from 'fastify';

/** 流媒体 CDN 的 Referer 校验白名单：命中才允许代理。 */
const PROXY_ALLOWED_HOST_SUFFIXES = [
  '.bilibili.com',
  '.hdslb.com',
  '.bilivideo.com',
  '.douyucdn.cn',
  '.douyucdn2.cn',
  '.huya.com',
  '.huyacdn.com',
  '.douyin.com',
  '.douyincdn.com',
  '.zjcdn.com',
  '.kuaishou.com',
  '.chenzhongtech.com',
  '.gifshow.com',
  '.flextv.kr',
];

/**
 * 直播流反向代理：流式透传（直播流无限长，绝不能整体缓冲进内存）。
 * 前端直连 CDN 被 CORS/Referer 拦截时，自动改走这里。
 */
export async function streamProxy(target: string, reply: FastifyReply): Promise<void> {
  let parsed: URL;
  try {
    parsed = new URL(target);
  } catch {
    return reply.code(400).send({ error: 'invalid url' });
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    return reply.code(400).send({ error: 'invalid protocol' });
  }
  const host = parsed.hostname;
  const hostOk = PROXY_ALLOWED_HOST_SUFFIXES.some((s) => host === s.slice(1) || host.endsWith(s));
  if (!hostOk) return reply.code(403).send({ error: 'host not allowed' });

  const headers: Record<string, string> = {
    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36',
    referer: `${parsed.protocol}//${parsed.hostname}/`,
    origin: `${parsed.protocol}//${parsed.hostname}`,
  };
  const range = reply.request.headers.range;
  if (typeof range === 'string') headers.range = range;

  const controller = new AbortController();
  // 客户端断开（切线路/退房间）时中止上游拉流
  reply.raw.on('close', () => controller.abort());

  try {
    const upstream = await fetch(target, { headers, redirect: 'follow', signal: controller.signal });
    if (upstream.status >= 400) {
      return reply.code(502).send({ error: `upstream ${upstream.status}` });
    }
    reply.code(upstream.status);
    const ct = upstream.headers.get('content-type');
    if (ct) reply.header('content-type', ct);
    const cl = upstream.headers.get('content-length');
    if (cl) reply.header('content-length', cl);
    const ar = upstream.headers.get('accept-ranges');
    if (ar) reply.header('accept-ranges', ar);
    reply.header('cache-control', 'no-cache');
    // 流式透传：手动 reader 循环泵数据（fromWeb 在部分 Node/undici 组合下不泵数据）
    const reader = upstream.body!.getReader();
    const nodeStream = new Readable({
      async read() {
        try {
          const { done, value } = await reader.read();
          this.push(done ? null : Buffer.from(value));
        } catch (e) {
          this.destroy(e as Error);
        }
      },
    });
    nodeStream.on('error', (e) => reply.log.error({ err: e }, 'proxy stream error'));
    // 关键：async handler 里 send 之后必须 return reply，否则 fastify 会在
    // handler resolve 时截断响应（表现为 200 但 0 字节）。
    return reply.send(nodeStream);
  } catch (err) {
    if (!reply.sent) reply.code(502).send({ error: 'upstream failed' });
  }
}
