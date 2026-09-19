"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parsePlayQualities = parsePlayQualities;
exports.getKuaishouEffectiveCookie = effectiveCookie;
/**
 * kuaishou 平台 API 聚合（移植自 lib/core/site/kuaishou_site.dart）。
 * - 匿名会话：请求房间页捕获 Set-Cookie（upstream.setCookies）+ registerDid 心跳，
 *   进程内缓存 30 分钟（Dart _sessionLifetime）。
 * - 详情：房间页 HTML window.__INITIAL_STATE__ 解析。
 * - 弹幕参数：danmakuData = liveStreamId 字符串（KuaishouDanmakuArgs.liveStreamId）。
 */
const index_1 = require("./index");
const protocol_1 = require("../protocol");
const upstream_1 = require("../upstream");
const cookies_1 = require("../auth/cookies");
const K_BASE_HEADERS = {
    'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36',
    accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3',
    connection: 'keep-alive',
    'sec-ch-ua': 'Google Chrome;v=107, Chromium;v=107, Not=A?Brand;v=24',
    'sec-ch-ua-platform': 'macOS',
    'sec-fetch-dest': 'document',
    'sec-fetch-mode': 'navigate',
    'sec-fetch-site': 'same-origin',
    'sec-fetch-user': '?1',
};
const IMAGE_EXTENSIONS = new Set([
    'svgz', 'pjp', 'png', 'ico', 'avif', 'tiff', 'tif', 'jfif', 'svg', 'xbm', 'pjpeg',
    'webp', 'jpg', 'jpeg', 'bmp', 'gif',
]);
function isImage(url) {
    if (url === '')
        return false;
    return IMAGE_EXTENSIONS.has(url.split('.').pop()?.toLowerCase() ?? '');
}
// 匿名会话进程内共享（Dart static 字段同构）
let sessionCookie = '';
const sessionCookieObj = new Map();
let sessionBootstrap = null;
let sessionUpdatedAt = 0;
const SESSION_LIFETIME_MS = 30 * 60 * 1000;
function effectiveCookie() {
    const configured = (0, cookies_1.getCookie)('kuaishou').trim();
    return configured !== '' ? configured : sessionCookie;
}
function roomHeaders() {
    const result = {
        ...K_BASE_HEADERS,
        'sec-ch-ua': 'Google Chrome;v=107, Chromium;v=107, Not=A?Brand;v=24',
        'sec-ch-ua-platform': 'macOS',
    };
    const cookie = effectiveCookie();
    if (cookie !== '')
        result['cookie'] = cookie;
    return result;
}
/** Dart getCookie(url)：GET 房间页捕获 Set-Cookie 组装会话。 */
async function captureSessionCookie(url) {
    const res = await (0, upstream_1.upstream)(url, { headers: K_BASE_HEADERS });
    const pairs = [];
    sessionCookieObj.clear();
    for (const raw of res.setCookies) {
        const pair = raw.split(';')[0].trim();
        if (pair === '' || !pair.includes('='))
            continue;
        const eq = pair.indexOf('=');
        const name = pair.substring(0, eq);
        const value = pair.substring(eq + 1);
        pairs.push(pair);
        sessionCookieObj.set(name, value);
    }
    sessionCookie = pairs.join(';');
}
/** Dart misc2dic：registerDid 心跳报文。 */
function misc2dic(did) {
    const sessionId = '1eb20f88-51ac-4ecf-8dc3-ace5aefcae4f';
    return {
        common: {
            identity_package: { device_id: did, global_id: '' },
            app_package: { language: 'zh-CN', platform: 10, container: 'WEB', product_name: 'KS_GAME_LIVE_PC' },
            device_package: {
                os_version: 'NT 6.1',
                model: 'Windows',
                ua: 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36',
            },
            need_encrypt: 'false',
            network_package: { type: 3 },
            h5_extra_attr: '{"sdk_name":"webLogger","sdk_version":"3.9.49","sdk_bundle":"log.common.js","app_version_name":"","host_product":"","resolution":"1600x900","screen_with":1600,"screen_height":900,"device_pixel_ratio":1,"domain":"https://live.kuaishou.com"}',
            global_attr: '{}',
        },
        logs: [
            {
                client_timestamp: Date.now(),
                client_increment_id: Math.floor(Math.random() * 8999) + 1000,
                session_id: sessionId,
                time_zone: 'GMT+08:00',
                event_package: {
                    task_event: {
                        type: 1,
                        status: 0,
                        operation_type: 1,
                        operation_direction: 0,
                        session_id: sessionId,
                        url_package: {
                            page: 'GAME_DETAL_PAGE',
                            identity: '5316c78e-f0b6-4be2-a076-c8f9d11ebc0a',
                            page_type: 2,
                            params: '{"game_id":1001,"game_name":"王者荣耀"}',
                        },
                        element_package: {},
                    },
                },
            },
        ],
    };
}
/** Dart registerDid：设备埋点上报（尽力而为，不阻塞房间元数据）。 */
async function registerDid() {
    const did = sessionCookieObj.get('did');
    if (did == null || did === '')
        return null;
    return (0, upstream_1.upstreamJson)('https://log-sdk.ksapisrv.com/rest/wd/common/log/collect/misc2?v=3.9.49&kpn=KS_GAME_LIVE_PC', { method: 'POST', headers: K_BASE_HEADERS, body: JSON.stringify(misc2dic(did)) });
}
async function ensureSession(url) {
    if ((0, cookies_1.getCookie)('kuaishou').trim() !== '')
        return;
    const now = Date.now();
    if (sessionCookie !== '' && now - sessionUpdatedAt < SESSION_LIFETIME_MS)
        return;
    sessionBootstrap ??= (async () => {
        await captureSessionCookie(url);
        sessionUpdatedAt = Date.now();
        try {
            await registerDid();
        }
        catch {
            // Device telemetry is best-effort and must not hold up room metadata.
        }
    })().finally(() => {
        sessionBootstrap = null;
    });
    return sessionBootstrap;
}
function asInt(value) {
    if (typeof value === 'number')
        return Math.trunc(value);
    return Number.parseInt(String(value ?? ''), 10) || 0;
}
/** 快手粉丝数：counts.fan 是带单位展示串（"152.7w"），换算纯数字串。 */
function parseFansCount(counts) {
    if (counts == null || typeof counts !== 'object')
        return '';
    const raw = String(counts['fan'] ?? '').trim();
    if (raw === '')
        return '';
    const match = /^(\d+(?:\.\d+)?)\s*([万亿kwKW]?)/.exec(raw);
    if (!match)
        return '';
    const value = Number.parseFloat(match[1]) || 0;
    const ratio = match[2] === '万' || match[2] === 'w' || match[2] === 'W'
        ? 10_000
        : match[2] === 'k' || match[2] === 'K'
            ? 1_000
            : match[2] === '亿'
                ? 100_000_000
                : 1;
    const count = Math.floor(value * ratio);
    return count > 0 ? String(count) : '';
}
function coverOf(poster) {
    const text = String(poster ?? '');
    return isImage(text) ? text : `${text}.jpg`;
}
function roomFromEntry(entry, includePlaybackData) {
    const { liveStream, author, gameInfo, liveStreamId, live, description } = entry;
    return {
        ...(0, protocol_1.emptyRoom)('kuaishou', String(author['id'] ?? '')),
        cover: coverOf(liveStream['poster']),
        watching: live ? String(gameInfo['watchingCount'] ?? '') : '0',
        onlineViewers: live ? String(gameInfo['watchingCount'] ?? '') : '0',
        audienceMetricType: 'onlineViewers',
        area: String(gameInfo['name'] ?? ''),
        title: description.split('\n').join(' '),
        nick: String(author['name'] ?? ''),
        avatar: String(author['avatar'] ?? ''),
        introduction: description,
        notice: description,
        followers: parseFansCount(author['counts']),
        status: live,
        liveStatus: live ? protocol_1.LiveStatus.live : protocol_1.LiveStatus.offline,
        link: liveStreamId,
        danmakuData: liveStreamId === '' ? undefined : liveStreamId,
        data: includePlaybackData ? liveStream['playUrls'] ?? undefined : undefined,
    };
}
/** Dart _loadRoom：__INITIAL_STATE__ 解析。 */
async function loadRoom(roomId, includePlaybackData, ensure) {
    const url = `https://live.kuaishou.com/u/${encodeURIComponent(roomId)}`;
    if (ensure)
        await ensureSession(url);
    const res = await (0, upstream_1.upstream)(url, { headers: roomHeaders() });
    if (res.status >= 400)
        throw new Error(`kuaishou room page upstream ${res.status}`);
    const text = /window\.__INITIAL_STATE__=(.*?);/.exec(res.text)?.[1] ?? '';
    if (text === '')
        throw new Error('Kuaishou initial state is missing');
    const jsonObj = JSON.parse(text.split('undefined').join('null'));
    const playList = jsonObj['liveroom']?.['playList'];
    if (!Array.isArray(playList) || playList.length === 0) {
        throw new Error('Kuaishou room metadata is missing');
    }
    const room = playList[0];
    const liveStream = room['liveStream'] && typeof room['liveStream'] === 'object' ? room['liveStream'] : {};
    const author = room['author'] && typeof room['author'] === 'object' ? room['author'] : {};
    const gameInfo = room['gameInfo'] && typeof room['gameInfo'] === 'object' ? room['gameInfo'] : {};
    const rawLiveState = room['isLiving'];
    const live = rawLiveState === true || rawLiveState === 1 || String(rawLiveState ?? '').toLowerCase() === 'true';
    const description = String(author['description'] ?? '');
    const liveStreamId = String(liveStream['id'] ?? '');
    return roomFromEntry({ liveStreamId, author, liveStream, gameInfo, description, live }, includePlaybackData);
}
/** Dart parsePlayQualities：房间页 {h264,hevc} 与列表 [descriptor] 双形态合并。 */
function parsePlayQualities(raw) {
    const descriptors = Array.isArray(raw) ? raw : [raw];
    const merged = new Map();
    for (const rawDescriptor of descriptors) {
        if (rawDescriptor == null || typeof rawDescriptor !== 'object')
            continue;
        let descriptor = rawDescriptor;
        // 优先 AVC（兼容性），HEVC 仅兜底
        for (const codec of ['h264', 'avc', 'hevc', 'h265']) {
            const candidate = rawDescriptor[codec];
            if (representationsOf(candidate).length > 0) {
                descriptor = candidate;
                break;
            }
        }
        for (const item of representationsOf(descriptor)) {
            if (item == null || typeof item !== 'object')
                continue;
            const url = String(item['url'] ?? '').trim();
            if (!/^https?:\/\//.test(url))
                continue;
            const sort = asIntOrNull(item['level']) ?? asIntOrNull(item['bitrate']) ?? 0;
            const name = String(item['name'] ?? '').trim() !== ''
                ? String(item['name']).trim()
                : String(item['shortName'] ?? '').trim() !== ''
                    ? String(item['shortName']).trim()
                    : String(item['qualityType'] ?? '').trim() !== ''
                        ? String(item['qualityType']).trim()
                        : `清晰度 ${sort}`;
            const key = `${name}\u0000${sort}`;
            const existing = merged.get(key);
            if (existing == null) {
                merged.set(key, { name, sort, urls: [url] });
            }
            else if (!existing.urls.includes(url)) {
                existing.urls.push(url);
            }
        }
    }
    const qualities = [...merged.values()].map((entry) => ({
        quality: entry.name,
        sort: entry.sort,
        data: entry.urls,
    }));
    qualities.sort((a, b) => b.sort - a.sort);
    return qualities;
}
function representationsOf(descriptor) {
    if (descriptor == null || typeof descriptor !== 'object')
        return [];
    const d = descriptor;
    const adaptationSet = d['adaptationSet'];
    const representations = adaptationSet != null && typeof adaptationSet === 'object'
        ? adaptationSet['representation']
        : d['representation'];
    return Array.isArray(representations) ? representations : [];
}
function asIntOrNull(value) {
    if (typeof value === 'number')
        return Math.trunc(value);
    const parsed = Number.parseInt(String(value ?? ''), 10);
    return Number.isNaN(parsed) ? null : parsed;
}
class KuaishouSite {
    async getCategories(_page, _pageSize) {
        const base = [
            { id: '1', name: '热门' },
            { id: '2', name: '网游' },
            { id: '3', name: '单机' },
            { id: '4', name: '手游' },
            { id: '5', name: '棋牌' },
            { id: '6', name: '娱乐' },
            { id: '7', name: '综合' },
            { id: '8', name: '文化' },
        ];
        const categories = [];
        for (const item of base) {
            const children = [];
            // Dart getAllSubCategores：翻页聚合直到一页不足 pageSize
            for (let page = 1;; page++) {
                const qs = new URLSearchParams({ type: item.id, page: String(page), size: '30' });
                const result = await (0, upstream_1.upstreamJson)(`https://live.kuaishou.com/live_api/category/data?${qs.toString()}`, { headers: K_BASE_HEADERS }).catch(() => null);
                const subs = result?.['data']?.['list'] ?? [];
                for (const sub of subs) {
                    children.push({
                        platform: 'kuaishou',
                        areaType: item.id,
                        typeName: item.name,
                        areaId: String(sub['id'] ?? ''),
                        areaName: String(sub['name'] ?? ''),
                        areaPic: String(sub['poster'] ?? ''),
                        shortName: '',
                    });
                }
                if (subs.length < 30)
                    break;
            }
            categories.push({ id: item.id, name: item.name, children });
        }
        return categories;
    }
    async getCategoryRooms(cateId, _typeName, page, _pageSize) {
        const api = cateId.length < 7
            ? 'https://live.kuaishou.com/live_api/gameboard/list'
            : 'https://live.kuaishou.com/live_api/non-gameboard/list';
        const qs = new URLSearchParams({ filterType: '0', pageSize: '20', gameId: cateId, page: String(page) });
        const result = await (0, upstream_1.upstreamJson)(`${api}?${qs.toString()}`, { headers: K_BASE_HEADERS });
        const items = [];
        for (const item of result['data']?.['list'] ?? []) {
            const liveStreamId = String(item['id'] ?? '');
            items.push(roomFromEntry({
                liveStreamId,
                author: item['author'] ?? {},
                liveStream: item['liveStream'] ?? {},
                gameInfo: item['gameInfo'] ?? {},
                description: String(item['caption'] ?? ''),
                live: true,
            }, true));
            // 列表项的 data 为 playUrls 原文（Dart data: item["playUrls"]）
            const last = items[items.length - 1];
            last.data = item['playUrls'] ?? undefined;
            last.title = String(item['caption'] ?? '');
            last.cover = isImage(String(item['poster'] ?? '')) ? String(item['poster'] ?? '') : `${String(item['poster'] ?? '')}.jpg`;
        }
        return items;
    }
    async getRecommendRooms(_page, _pageSize) {
        const result = await (0, upstream_1.upstreamJson)('https://live.kuaishou.com/live_api/home/list', {
            headers: K_BASE_HEADERS,
        });
        const items = [];
        for (const item of result['data']?.['list'] ?? []) {
            for (const sitem of item['gameLiveInfo'] ?? []) {
                for (const titem of sitem['liveInfo'] ?? []) {
                    const author = titem['author'] ?? {};
                    const gameInfo = titem['gameInfo'] ?? {};
                    const liveStreamId = String(titem['id'] ?? '');
                    const description = author['description'] != null ? String(author['description']) : '';
                    const room = roomFromEntry({
                        liveStreamId,
                        author,
                        liveStream: titem,
                        gameInfo,
                        description,
                        live: true,
                    }, true);
                    room.cover = String(gameInfo['poster'] ?? '');
                    room.data = titem['playUrls'] ?? undefined;
                    room.notice = description;
                    items.push(room);
                }
            }
        }
        return items;
    }
    async getRoomDetail(roomId) {
        return loadRoom(roomId, true, true);
    }
    async getPlayQualites(roomId) {
        const detail = await this.getRoomDetail(roomId);
        const qualities = parsePlayQualities(detail.data);
        if (qualities.length === 0) {
            throw new Error('Kuaishou room has no playable live or replay stream');
        }
        return qualities;
    }
    async getPlayUrls(roomId, quality) {
        const qualities = await this.getPlayQualites(roomId);
        const matched = qualities.find((item) => item.quality === quality) ??
            (qualities.length > 0 ? qualities[0] : undefined);
        return matched ? matched.data : [];
    }
    async getLiveStatus(roomId) {
        // 匿名房间页一般可访问；失败带会话重试一次（Dart 同款）
        const room = await loadRoom(roomId, false, false).catch(() => loadRoom(roomId, false, true));
        return room.liveStatus === protocol_1.LiveStatus.live;
    }
    async searchRooms(_keyword, _page, _pageSize) {
        // 快手无法搜索主播，只能搜索游戏分类，这里不做展示
        return [];
    }
    async searchAnchors(_keyword, _page, _pageSize) {
        return [];
    }
    async sendDanmaku(_roomId, _message) {
        // 快手 web 发送评论需要登录态与 __NS_sig3 签名，暂不支持
        return [false, '快手暂不支持发送弹幕'];
    }
}
(0, index_1.registerSite)('kuaishou', new KuaishouSite());
