import { getStoredCookie } from './store';

/**
 * 平台 cookie 托管读取入口（site 实现统一调用）。
 * 优先级：内存缓存 → 加密存储（routes/auth 写入）→ 环境变量。
 */

const memCookies = new Map<string, string>();

function fromEnv(platform: string): string {
  const key = `PURE_LIVE_COOKIE_${platform.toUpperCase()}`;
  return process.env[key] ?? '';
}

export function getCookie(platform: string): string {
  const cached = memCookies.get(platform);
  if (cached !== undefined) return cached;
  const stored = getStoredCookie(platform);
  if (stored) {
    memCookies.set(platform, stored);
    return stored;
  }
  return fromEnv(platform);
}

export function setCookie(platform: string, cookie: string): void {
  if (cookie) {
    memCookies.set(platform, cookie);
  } else {
    memCookies.delete(platform);
  }
}
