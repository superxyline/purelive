/**
 * 平台 cookie 托管（M5 将替换为 AES 加密落盘）。
 * 当前版本：环境变量 / 内存缓存，供各平台 site 实现统一取用。
 */

const memCookies = new Map<string, string>();

function fromEnv(platform: string): string {
  const key = `PURE_LIVE_COOKIE_${platform.toUpperCase()}`;
  return process.env[key] ?? '';
}

export function getCookie(platform: string): string {
  return memCookies.get(platform) ?? fromEnv(platform);
}

export function setCookie(platform: string, cookie: string): void {
  memCookies.set(platform, cookie);
}
