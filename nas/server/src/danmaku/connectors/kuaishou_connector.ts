/**
 * 快手弹幕 Connector（移植自 lib/core/danmaku/kuaishou_danmaku.dart）。
 * 匿名 HTTP 增量长轮询（cursor 渐进，liveStreamFeeds），转推统一 JSON；
 * 轮询一次性、串行调度，pullCycleSeconds 控制节奏（下限 1s），指数退避重连最多 8 次。
 * 弹幕参数为 liveStreamId（kuaishou site 的 danmakuData）。
 */
import type { DanmakuMessageJson } from '../../protocol';
import { upstream, upstreamJson } from '../../upstream';
import { getKuaishouEffectiveCookie } from '../../sites/kuaishou';
import { getSite } from '../../sites';
import { registerConnector, type DanmakuSender } from '../registry';

const FEED_URLS = [
  'https://livev.m.chenzhongtech.com/wap/live/feed',
  'https://m.gifshow.com/wap/live/feed',
];
const MAX_RECONNECT_ATTEMPTS = 8;
const MINIMUM_POLL_DELAY_MS = 1_000;
const K_FEED_UA =
  'Mozilla/5.0 (Linux; Android 16; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0 Mobile Safari/537.36';

interface KuaishouFeedBatch {
  cursor: string;
  pullDelayMs: number;
  messages: DanmakuMessageJson[];
  onlineViewers: number | null;
}

export class KuaishouConnector {
  private liveStreamId = '';
  private cursor = '';
  private generation = 0;
  private pollTimer: NodeJS.Timeout | null = null;
  private reconnectAttempts = 0;
  private stopped = false;

  constructor(
    private readonly roomId: string,
    danmakuData: unknown,
    private readonly send: DanmakuSender,
  ) {
    // danmakuData 为 liveStreamId 字符串（kuaishou site）
    if (typeof danmakuData === 'string' && danmakuData.trim() !== '') {
      this.liveStreamId = danmakuData;
    }
  }

  async start(): Promise<void> {
    if (this.liveStreamId === '') {
      this.liveStreamId = await this.resolveLiveStreamId();
    }
    if (this.liveStreamId.trim() === '') {
      throw new Error('Kuaishou live stream id is missing');
    }
    const generation = ++this.generation;
    let lastError: unknown = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await delay(attempt === 1 ? 600 : 1400);
      }
      if (generation !== this.generation) return;
      try {
        await this.pollOnce(generation);
        return;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  private async resolveLiveStreamId(): Promise<string> {
    const detail = await getSite('kuaishou').getRoomDetail(this.roomId);
    if (typeof detail.danmakuData === 'string' && detail.danmakuData !== '') {
      return detail.danmakuData;
    }
    return detail.link ?? '';
  }

  private async fetchFeed(liveStreamId: string, cursor: string): Promise<unknown> {
    const headers: Record<string, string> = {
      'user-agent': K_FEED_UA,
      accept: 'application/json, text/plain, */*',
      referer: 'https://livev.m.chenzhongtech.com/',
    };
    const cookie = getKuaishouEffectiveCookie().trim();
    if (cookie !== '') headers['cookie'] = cookie;
    let lastError: unknown = null;
    for (const endpoint of FEED_URLS) {
      try {
        const qs = new URLSearchParams({ liveStreamId });
        if (cursor !== '') qs.set('cursor', cursor);
        return await upstreamJson(`${endpoint}?${qs.toString()}`, { headers });
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError;
  }

  private async pollOnce(generation: number, propagateFailure = true): Promise<void> {
    try {
      const raw = await this.fetchFeed(this.liveStreamId, this.cursor);
      if (generation !== this.generation) return;
      const batch = parseFeedPayload(raw);
      if (batch.cursor !== '') this.cursor = batch.cursor;
      this.reconnectAttempts = 0;

      if (batch.onlineViewers != null) {
        this.send({ type: 'online', onlineCount: batch.onlineViewers });
      }
      for (const message of batch.messages) {
        if (generation !== this.generation) return;
        this.send(message);
      }
      this.schedulePoll(generation, batch.pullDelayMs);
    } catch (error) {
      if (generation !== this.generation) return;
      if (propagateFailure && this.reconnectAttempts === 0 && this.cursor === '') {
        throw error;
      }
      this.handlePollFailure(generation, error);
    }
  }

  private handlePollFailure(generation: number, error: unknown): void {
    this.reconnectAttempts++;
    if (this.reconnectAttempts > MAX_RECONNECT_ATTEMPTS) {
      // 超过最大重连次数：停止轮询
      this.generation++;
      return;
    }
    const seconds = 1 << Math.min(Math.max(this.reconnectAttempts - 1, 0), 3);
    this.schedulePoll(generation, seconds * 1000);
    void error;
  }

  private schedulePoll(generation: number, requestedDelayMs: number): void {
    if (generation !== this.generation) return;
    if (this.pollTimer) clearTimeout(this.pollTimer);
    const delayMs = Math.max(requestedDelayMs, MINIMUM_POLL_DELAY_MS);
    this.pollTimer = setTimeout(() => {
      this.pollTimer = null;
      if (generation === this.generation) {
        void this.pollOnce(generation, false).catch(() => {
          // 后续轮询失败在 pollOnce 内部处理
        });
      }
    }, delayMs);
    this.pollTimer.unref?.();
  }

  stop(): void {
    this.stopped = true;
    this.generation++;
    if (this.pollTimer) {
      clearTimeout(this.pollTimer);
      this.pollTimer = null;
    }
    this.cursor = '';
    this.reconnectAttempts = 0;
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function asInt(value: unknown): number {
  if (typeof value === 'number') return Math.trunc(value);
  return Number.parseInt(String(value ?? ''), 10) || 0;
}

/** Dart parseFeedPayload：剥壳 → result/cursor/pullCycleSeconds/currentWatchingCount。 */
function parseFeedPayload(raw: unknown): KuaishouFeedBatch {
  let payload = raw;
  for (let depth = 0; depth < 3 && typeof payload === 'string'; depth++) {
    payload = JSON.parse(payload);
  }
  if (payload != null && typeof payload === 'object' && (payload as Record<string, unknown>)['data'] != null) {
    payload = (payload as Record<string, unknown>)['data'];
  }
  if (payload == null || typeof payload !== 'object') {
    throw new Error('Kuaishou feed has an invalid shape');
  }
  const data = payload as Record<string, any>;

  const result = asInt(data['result']);
  if (result !== 1) {
    throw new Error(`Kuaishou feed rejected the request (result: ${data['result'] ?? 'unknown'})`);
  }
  const cursor = String(data['cursor'] ?? '');
  const pullSeconds = Math.min(Math.max(asInt(data['pullCycleSeconds']) || 3, 1), 10);
  const watchingText = String(data['currentWatchingCount'] ?? '').trim();
  const onlineViewers = watchingText === '' ? null : parseAudienceNumber(watchingText);
  const messages: DanmakuMessageJson[] = [];

  const feeds = data['liveStreamFeeds'];
  if (Array.isArray(feeds)) {
    for (const feed of feeds) {
      if (feed == null || typeof feed !== 'object') continue;
      const type = String(feed['type'] ?? '').toLowerCase();
      if (type === 'comment') {
        const message = parseComment(feed);
        if (message != null) messages.push(message);
      } else if (type === 'gift') {
        const message = parseGift(feed);
        if (message != null) messages.push(message);
      }
    }
  }

  return { cursor, pullDelayMs: pullSeconds * 1000, messages, onlineViewers };
}

function parseComment(feed: Record<string, any>): DanmakuMessageJson | null {
  const content = String(feed['content'] ?? '').trim();
  if (content === '') return null;
  const author = feed['author'] != null && typeof feed['author'] === 'object' ? feed['author'] : {};
  const userName = String(author['userName'] ?? '').trim();
  const userId = String(author['userId'] ?? '');
  const timestamp = feed['time'] != null ? asInt(feed['time']) : null;
  const rawId = String(feed['id'] ?? '').trim();
  void rawId;
  return {
    type: 'msg',
    userName: userName === '' ? '快手用户' : userName,
    message: content,
    subMessage: userId === '' ? undefined : userId,
  };
}

/** 尽力解析礼物 feed；提取不到礼物名即视为不可展示丢弃。 */
function parseGift(feed: Record<string, any>): DanmakuMessageJson | null {
  const author = feed['author'] != null && typeof feed['author'] === 'object' ? feed['author'] : {};
  const userName = String(author['userName'] ?? '').trim();
  const userId = String(author['userId'] ?? '');

  const candidates = [feed['gift'], feed['giftInfo'], feed['sendGiftInfo'], feed];
  let giftData: Record<string, any> = {};
  for (const candidate of candidates) {
    if (candidate != null && typeof candidate === 'object') {
      giftData = candidate;
      if ((giftData['giftName'] ?? giftData['name']) != null) break;
    }
  }
  const giftName =
    String(giftData['giftName'] ?? giftData['name'] ?? feed['giftName'] ?? feed['displayText'] ?? '').trim() ?? '';
  if (giftName === '') return null;

  const giftCount =
    asInt(feed['num'] ?? feed['sortNum'] ?? feed['giftCount'] ?? giftData['num'] ?? 1) || 1;

  return {
    type: 'gift',
    userName: userName === '' ? '快手用户' : userName,
    message: `${userName === '' ? '快手用户' : userName} 送出 ${giftName} ×${giftCount}`,
    giftName,
    giftCount,
    giftPrice: priceOf(giftData, feed),
    giftColor: '#FF6699',
    subMessage: userId === '' ? undefined : userId,
  };
}

function priceOf(giftData: Record<string, any>, feed: Record<string, any>): number | undefined {
  const raw = giftData['price'] ?? feed['price'];
  if (raw == null) return undefined;
  const parsed = Number.parseFloat(String(raw));
  return Number.isNaN(parsed) ? undefined : parsed;
}

/** LiveRoom.parseAudienceNumber：处理 "1.2万"/"3.4w" 等展示串。 */
function parseAudienceNumber(text: string): number {
  const raw = text.trim();
  if (raw === '') return 0;
  const match = /^([\d.,]+)\s*([万亿kwKW]?)/.exec(raw);
  if (!match) return 0;
  const value = Number.parseFloat(match[1].replace(/,/g, ''));
  if (Number.isNaN(value)) return 0;
  const ratio =
    match[2] === '万' || match[2] === 'w' || match[2] === 'W'
      ? 10_000
      : match[2] === '亿'
        ? 100_000_000
        : match[2] === 'k' || match[2] === 'K'
          ? 1_000
          : 1;
  return Math.floor(value * ratio);
}

registerConnector('kuaishou', (roomId, danmakuData, send) => new KuaishouConnector(roomId, danmakuData, send));
