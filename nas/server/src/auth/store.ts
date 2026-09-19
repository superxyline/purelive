import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

/**
 * 平台 cookie 加密存储：AES-256-GCM。
 * 主密钥来自环境变量 NAS_MASTER_KEY；未设置时自动生成并保存到数据目录。
 * 数据文件为 {platform: cookieString} 的 JSON，加密后落盘。
 */

const DATA_DIR = process.env.PURE_LIVE_DATA_DIR || path.join(process.cwd(), '..', 'data');
const STORE_FILE = path.join(DATA_DIR, 'cookies.enc');
const MASTER_KEY_FILE = path.join(DATA_DIR, '.masterkey');

function ensureDataDir(): void {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

function getMasterKey(): Buffer {
  ensureDataDir();
  const fromEnv = process.env.NAS_MASTER_KEY;
  if (fromEnv && fromEnv.length >= 16) {
    return crypto.createHash('sha256').update(fromEnv).digest();
  }
  if (fs.existsSync(MASTER_KEY_FILE)) {
    return Buffer.from(fs.readFileSync(MASTER_KEY_FILE, 'utf8'), 'hex');
  }
  const key = crypto.randomBytes(32);
  fs.writeFileSync(MASTER_KEY_FILE, key.toString('hex'), { mode: 0o600 });
  return key;
}

interface EncryptedPayload {
  iv: string;
  tag: string;
  data: string;
}

function readStore(): Record<string, string> {
  if (!fs.existsSync(STORE_FILE)) return {};
  try {
    const payload = JSON.parse(fs.readFileSync(STORE_FILE, 'utf8')) as EncryptedPayload;
    const decipher = crypto.createDecipheriv('aes-256-gcm', getMasterKey(), Buffer.from(payload.iv, 'hex'));
    decipher.setAuthTag(Buffer.from(payload.tag, 'hex'));
    const plain = Buffer.concat([decipher.update(Buffer.from(payload.data, 'hex')), decipher.final()]);
    return JSON.parse(plain.toString('utf8'));
  } catch (_) {
    return {};
  }
}

function writeStore(cookies: Record<string, string>): void {
  ensureDataDir();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getMasterKey(), iv);
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(cookies), 'utf8'), cipher.final()]);
  const payload: EncryptedPayload = {
    iv: iv.toString('hex'),
    tag: cipher.getAuthTag().toString('hex'),
    data: encrypted.toString('hex'),
  };
  fs.writeFileSync(STORE_FILE, JSON.stringify(payload), { mode: 0o600 });
}

export function getStoredCookie(platform: string): string {
  return readStore()[platform] ?? '';
}

export function setStoredCookie(platform: string, cookie: string): void {
  const cookies = readStore();
  if (cookie) {
    cookies[platform] = cookie;
  } else {
    delete cookies[platform];
  }
  writeStore(cookies);
}

export function hasStoredCookie(platform: string): boolean {
  return getStoredCookie(platform).length > 0;
}

export function allPlatformsStatus(platforms: string[]): Record<string, boolean> {
  const cookies = readStore();
  return Object.fromEntries(platforms.map((p) => [p, Boolean(cookies[p])]));
}
