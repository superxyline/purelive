"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_DESKTOP_UA = void 0;
exports.upstream = upstream;
exports.upstreamJson = upstreamJson;
exports.upstreamForm = upstreamForm;
exports.DEFAULT_DESKTOP_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';
/** 请求上游平台接口：统一超时、UA 兜底、Set-Cookie 捕获。基于 Node 20 内置 fetch。 */
async function upstream(url, opts = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 20_000);
    try {
        const res = await fetch(url, {
            method: opts.method ?? 'GET',
            headers: { 'user-agent': exports.DEFAULT_DESKTOP_UA, ...(opts.headers ?? {}) },
            body: opts.body,
            redirect: opts.redirect ?? 'follow',
            signal: controller.signal,
        });
        const headers = {};
        res.headers.forEach((v, k) => {
            headers[k.toLowerCase()] = v;
        });
        const setCookies = res.headers.getSetCookie?.() ?? [];
        const text = await res.text();
        return { status: res.status, headers, setCookies, text };
    }
    finally {
        clearTimeout(timer);
    }
}
async function upstreamJson(url, opts = {}) {
    const res = await upstream(url, opts);
    if (res.status >= 400)
        throw new Error(`upstream ${res.status} for ${url}`);
    return JSON.parse(res.text);
}
async function upstreamForm(url, form, opts = {}) {
    const body = new URLSearchParams(form).toString();
    return upstream(url, {
        ...opts,
        method: 'POST',
        body,
        headers: { 'content-type': 'application/x-www-form-urlencoded', ...(opts.headers ?? {}) },
    });
}
