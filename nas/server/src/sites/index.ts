import type { Platform } from '../protocol';
import type { Site } from './types';

export * from './types';

const registry = new Map<Platform, Site>();

export function registerSite(platform: Platform, site: Site): void {
  registry.set(platform, site);
}

export function getSite(platform: string): Site {
  const site = registry.get(platform as Platform);
  if (!site) throw Object.assign(new Error(`unknown platform: ${platform}`), { statusCode: 404 });
  return site;
}

export function allSites(): Map<Platform, Site> {
  return registry;
}

// 各平台实现（按移植进度逐个启用）
import './bilibili';
import './douyu';
import './huya';
import './douyin';
import './kuaishou';
