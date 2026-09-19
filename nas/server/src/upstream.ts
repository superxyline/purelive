import { FastifyInstance } from 'fastify';

export const DEFAULT_DESKTOP_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

export interface UpstreamOptions {
  method?: 'GET' | 'POST' | 'HEAD';
  headers?: Record<string, string>;
  body?: string | Uint8Array;
  timeoutMs?: number;
  /** 不跟随重定向（部分平台登录轮询需要检查 3xx） */
  redirect?: 'follow' | 'manual' | 'error';
}

export interface UpstreamResponse {
  status: number;
  headers: Record<string, string>;
  /** 所有 Set-Cookie 原始值（登录/匿名会话捕获需要） */
  setCookies: string[];
  text: string;
}

/** 请求上游平台接口：统一超时、UA 兜底、Set-Cookie 捕获。基于 Node 20 内置 fetch。 */
export async function upstream(url: string, opts: UpstreamOptions = {}): Promise<UpstreamResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 20_000);
  try {
    const res = await fetch(url, {
      method: opts.method ?? 'GET',
      headers: { 'user-agent': DEFAULT_DESKTOP_UA, ...(opts.headers ?? {}) },
      body: opts.body,
      redirect: opts.redirect ?? 'follow',
      signal: controller.signal,
    });
    const headers: Record<string, string> = {};
    res.headers.forEach((v, k) => {
      headers[k.toLowerCase()] = v;
    });
    const setCookies = (res.headers as any).getSetCookie?.() ?? [];
    const text = await res.text();
    return { status: res.status, headers, setCookies, text };
  } finally {
    clearTimeout(timer);
  }
}

export async function upstreamJson<T = any>(url: string, opts: UpstreamOptions = {}): Promise<T> {
  const res = await upstream(url, opts);
  if (res.status >= 400) throw new Error(`upstream ${res.status} for ${url}`);
  return JSON.parse(res.text) as T;
}

export async function upstreamForm(
  url: string,
  form: Record<string, string>,
  opts: UpstreamOptions = {},
): Promise<UpstreamResponse> {
  const body = new URLSearchParams(form).toString();
  return upstream(url, {
    ...opts,
    method: 'POST',
    body,
    headers: { 'content-type': 'application/x-www-form-urlencoded', ...(opts.headers ?? {}) },
  });
}

/** 把 Fastify 实例类型引出来仅供类型标注使用 */
export type _F = FastifyInstance;
