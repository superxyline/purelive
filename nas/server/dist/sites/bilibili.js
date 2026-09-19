"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * bilibili 平台 API 聚合（移植自 lib/core/site/bilibili_site.dart）。
 * URL / query / header / 响应解析与 Dart 实现逐字段对应；
 * cookie 改用 auth.getCookie('bilibili')，uid 从 cookie 的 DedeUserID 提取。
 */
const crypto_1 = require("crypto");
const index_1 = require("./index");
const protocol_1 = require("../protocol");
const upstream_1 = require("../upstream");
const cookies_1 = require("../auth/cookies");
const K_USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';
const K_DEFAULT_REFERER = 'https://live.bilibili.com/';
// buvid 与账号无关，是设备级标识：模块级缓存，避免批量刷新时每房间重复请求 spi。
let buvid3 = '';
let buvid4 = '';
let accessId = '';
// WBI key（6 小时缓存）
let kImgKey = '';
let kSubKey = '';
let wbiKeysUpdatedAt = 0;
const MIXIN_KEY_ENC_TAB = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38,
    41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36,
    20, 34, 44, 52,
];
function md5Hex(text) {
    return (0, crypto_1.createHash)('md5').update(text, 'utf8').digest('hex');
}
/** Dart SettingsService.bilibiliUid 的替代：从登录 cookie 提取 DedeUserID。 */
function getUserId() {
    const match = /DedeUserID=(\d+)/i.exec((0, cookies_1.getCookie)('bilibili'));
    return match ? Number(match[1]) : 0;
}
function getBuvidFromCookie() {
    const cookie = (0, cookies_1.getCookie)('bilibili');
    const b3 = /buvid3=(.*?);/.exec(cookie)?.[1] ?? '';
    const b4 = /buvid4=(.*?);/.exec(cookie)?.[1] ?? '';
    return { b_3: b3, b_4: b4 };
}
/** /x/frontend/finger/spi 获取设备级 buvid（失败返回空串，不阻塞取流）。 */
async function getBuvid() {
    try {
        const cookie = (0, cookies_1.getCookie)('bilibili');
        if (cookie.includes('buvid3')) {
            return getBuvidFromCookie();
        }
        const result = await (0, upstream_1.upstreamJson)('https://api.bilibili.com/x/frontend/finger/spi', {
            headers: { 'user-agent': K_USER_AGENT, referer: K_DEFAULT_REFERER, cookie },
        });
        return { b_3: String(result?.data?.b_3 ?? ''), b_4: String(result?.data?.b_4 ?? '') };
    }
    catch {
        return { b_3: '', b_4: '' };
    }
}
async function getHeader() {
    if (buvid3 === '') {
        const buvidInfo = await getBuvid();
        buvid3 = buvidInfo.b_3 ?? '';
        buvid4 = buvidInfo.b_4 ?? '';
    }
    const cookie = (0, cookies_1.getCookie)('bilibili');
    if (cookie === '') {
        return {
            'user-agent': K_USER_AGENT,
            referer: K_DEFAULT_REFERER,
            cookie: `buvid3=${buvid3};buvid4=${buvid4};`,
        };
    }
    return {
        cookie: cookie.includes('buvid3') ? cookie : `${cookie};buvid3=${buvid3};buvid4=${buvid4};`,
        'user-agent': K_USER_AGENT,
        referer: K_DEFAULT_REFERER,
    };
}
/** dio getJson 等价：URL + queryParameters（值 toString），JSON 解析。 */
async function getJson(url, params, header) {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(params))
        qs.set(k, String(v));
    const query = qs.toString();
    return (0, upstream_1.upstreamJson)(query ? `${url}?${query}` : url, { headers: header });
}
/** Dart Uri.encodeQueryComponent：除 unreserved 与 !'()* 外全部转义，空格为 '+'。 */
function encodeQueryComponent(value) {
    return encodeURIComponent(value).replace(/%20/g, '+');
}
async function getWbiKeys(forceRefresh = false) {
    const cacheAge = wbiKeysUpdatedAt === 0 ? null : Date.now() - wbiKeysUpdatedAt;
    if (!forceRefresh && kImgKey !== '' && kSubKey !== '' && cacheAge !== null && cacheAge < 6 * 3600 * 1000) {
        return [kImgKey, kSubKey];
    }
    // 获取最新的 img_key 和 sub_key
    const resp = await getJson('https://api.bilibili.com/x/web-interface/nav', {}, await getHeader());
    const imgUrl = String(resp?.data?.wbi_img?.img_url ?? '');
    const subUrl = String(resp?.data?.wbi_img?.sub_url ?? '');
    const imgKey = imgUrl.substring(imgUrl.lastIndexOf('/') + 1).split('.')[0] ?? '';
    const subKey = subUrl.substring(subUrl.lastIndexOf('/') + 1).split('.')[0] ?? '';
    kImgKey = imgKey;
    kSubKey = subKey;
    wbiKeysUpdatedAt = Date.now();
    return [imgKey, subKey];
}
function getMixinKey(origin) {
    // 对 imgKey 和 subKey 进行字符顺序打乱编码
    return MIXIN_KEY_ENC_TAB.reduce((s, i) => s + origin[i], '').substring(0, 32);
}
/** WBI 签名：返回补上 wts/w_rid 后的完整 query 参数（对应 Dart getWbiSign）。 */
async function getWbiSign(url, forceRefresh = false) {
    const [imgKey, subKey] = await getWbiKeys(forceRefresh);
    const mixinKey = getMixinKey(imgKey + subKey);
    const currentTime = Math.floor(Date.now() / 1000);
    const queryParams = {};
    for (const [k, v] of new URL(url).searchParams)
        queryParams[k] = v;
    queryParams['wts'] = String(currentTime); // 添加 wts 字段
    // 按照 key 重排参数，并过滤 value 中的 "!'()*" 字符
    const sorted = Object.keys(queryParams).sort();
    const query = sorted
        .map((key) => {
        const value = queryParams[key]
            .split('')
            .filter((c) => !"!'()*".includes(c))
            .join('');
        return `${key}=${encodeQueryComponent(value)}`;
    })
        .join('&');
    queryParams['w_rid'] = md5Hex(`${query}${mixinKey}`);
    return queryParams;
}
/** getInfoByRoom：WBI key 过期返回 code=-352 时重试并强制刷新 WBI key。 */
async function getRoomInfo(roomId) {
    const baseUrl = 'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom';
    const url = `${baseUrl}?room_id=${roomId}`;
    let lastError;
    for (let attempt = 0; attempt < 2; attempt++) {
        try {
            const queryParams = await getWbiSign(url, attempt > 0);
            const result = await getJson(baseUrl, queryParams, await getHeader());
            if (result && typeof result === 'object' && result['code'] !== 0) {
                throw new Error(`getInfoByRoom code=${result['code']}`);
            }
            return result['data'];
        }
        catch (error) {
            lastError = error;
            if (attempt === 0)
                await new Promise((r) => setTimeout(r, 180));
        }
    }
    throw new Error(`Bilibili room info failed after WBI refresh: ${String(lastError)}`);
}
/** getInfoByRoom 里的主播粉丝数：anchor_info.relation_info.attention（单数字段）。 */
function parseFollowersFromRoomInfo(roomInfo) {
    if (!roomInfo || typeof roomInfo !== 'object')
        return '';
    const relationInfo = roomInfo?.['anchor_info']?.['relation_info'];
    return relationInfo?.['attention'] != null ? String(relationInfo['attention']) : '';
}
/** 从直播间网页内嵌的 "relation_info":{"attention":<粉丝数>} 抓取（接口风控兜底）。 */
async function fetchFollowersFromRoomPage(realRoomId) {
    if (realRoomId === '')
        return null;
    try {
        const res = await (0, upstream_1.upstream)(`https://live.bilibili.com/${realRoomId}`, { headers: await getHeader() });
        const html = res.text;
        const anchor = html.indexOf('"relation_info"');
        if (anchor < 0)
            return null;
        const end = anchor + 300 < html.length ? anchor + 300 : html.length;
        return /"attention"\s*:\s*(\d+)/.exec(html.substring(anchor, end))?.[1] ?? null;
    }
    catch {
        return null;
    }
}
/** getDanmuInfo 弹幕握手凭据（WBI 签名，带重试）。 */
async function discoverDanmaku(realRoomId, maxAttempts = 4) {
    const baseUrl = 'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo';
    const headers = await getHeader();
    let data;
    let lastError;
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
        try {
            const signed = await getWbiSign(`${baseUrl}?id=${realRoomId}&type=0`, attempt === 1 || attempt === 3);
            const response = await getJson(baseUrl, signed, headers);
            const candidate = response?.['data'];
            if (response?.['code'] === 0 && candidate && typeof candidate === 'object' && String(candidate['token'] ?? '') !== '') {
                data = candidate;
                break;
            }
            lastError = new Error(`getDanmuInfo code=${response?.['code']}`);
        }
        catch (error) {
            lastError = error;
        }
        if (attempt + 1 < maxAttempts) {
            await new Promise((r) => setTimeout(r, 180 * (attempt + 1)));
        }
    }
    if (!data)
        throw new Error(`Bilibili danmaku discovery failed: ${String(lastError)}`);
    // 官方公共网关优先（部分 ISP DNS 缺失 regional comet 记录），regional 节点作 failover。
    const officialFallback = 'wss://broadcastlv.chat.bilibili.com/sub';
    const serverUrls = [officialFallback];
    for (const item of data['host_list'] ?? []) {
        const host = String(item?.['host'] ?? '').trim();
        if (host === '')
            continue;
        const port = Number.parseInt(String(item?.['wss_port'] ?? ''), 10) || 443;
        const endpoint = `wss://${host}${port === 443 ? '' : `:${port}`}/sub`;
        if (!serverUrls.includes(endpoint))
            serverUrls.push(endpoint);
    }
    const uid = (0, cookies_1.getCookie)('bilibili').trim() === '' ? 0 : getUserId();
    const danmakuHeaders = {
        'user-agent': headers['user-agent'] ?? K_USER_AGENT,
        origin: 'https://live.bilibili.com',
        referer: `https://live.bilibili.com/${realRoomId}`,
    };
    if ((headers['cookie'] ?? '') !== '')
        danmakuHeaders['cookie'] = headers['cookie'];
    return {
        roomId: realRoomId,
        // 未登录时匿名弹幕 uid=0：带 uid 无 cookie 的 auth 包会被网关断开。
        uid,
        token: String(data['token'] ?? ''),
        serverUrls,
        buvid: buvid3,
        cookie: headers['cookie'] ?? (0, cookies_1.getCookie)('bilibili'),
        headers: danmakuHeaders,
    };
}
/** 未完成握手时的默认弹幕参数（进入房间后由弹幕层刷新凭据）。 */
function defaultDanmakuArgs(realRoomId) {
    const headers = {
        'user-agent': K_USER_AGENT,
        origin: 'https://live.bilibili.com',
        referer: `https://live.bilibili.com/${realRoomId}`,
    };
    const cookie = (0, cookies_1.getCookie)('bilibili').trim() === '' ? `buvid3=${buvid3};buvid4=${buvid4};` : (0, cookies_1.getCookie)('bilibili');
    if (cookie !== '')
        headers['cookie'] = cookie;
    return {
        roomId: realRoomId,
        uid: (0, cookies_1.getCookie)('bilibili').trim() === '' ? 0 : getUserId(),
        token: '',
        serverUrls: ['wss://broadcastlv.chat.bilibili.com/sub'],
        buvid: buvid3,
        cookie,
        headers,
    };
}
/** Dart normalizeNetworkImageUrl 移植：协议相对/无 scheme 链接归一化。 */
function normalizeNetworkImageUrl(source) {
    let value = String(source ?? '').trim();
    if (value === '' || value.toLowerCase() === 'null')
        return '';
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1).trim();
    }
    if (value === '')
        return '';
    if (value.startsWith('//'))
        return `https:${value}`;
    try {
        const uri = new URL(value);
        if ((uri.protocol === 'http:' || uri.protocol === 'https:') && uri.hostname !== '')
            return value;
    }
    catch {
        // not absolute
    }
    if (!value.includes(' ') && /^[\w.-]+\.[a-zA-Z]{2,}([/:?#]|$)/.test(value)) {
        return `https://${value}`;
    }
    return '';
}
/** webMain 与旧匿名兜底接口共用的推荐列表解析（对应 Dart parseRecommendRooms）。 */
function parseRecommendRooms(response) {
    if (!response || typeof response !== 'object')
        throw new Error('Bilibili response is not an object');
    if (response['code'] !== 0) {
        throw new Error(`Bilibili API code=${response['code']}: ${response['message']}`);
    }
    const data = response['data'];
    const rawList = data && typeof data === 'object' ? data['recommend_room_list'] : data;
    if (!Array.isArray(rawList))
        throw new Error('Bilibili recommendation list is missing');
    const items = [];
    for (const raw of rawList) {
        if (!raw || typeof raw !== 'object')
            continue;
        const item = raw;
        const roomId = String(item['roomid'] ?? item['room_id'] ?? '');
        const cover = normalizeNetworkImageUrl(String(item['cover'] ?? item['user_cover'] ?? ''));
        items.push({
            ...(0, protocol_1.emptyRoom)('bilibili', roomId),
            title: String(item['title'] ?? ''),
            cover: cover === '' ? '' : `${cover}@400w.jpg`,
            area: String(item['area_v2_name'] ?? item['area_name'] ?? item['areaName'] ?? ''),
            nick: String(item['uname'] ?? ''),
            avatar: normalizeNetworkImageUrl(String(item['face'] ?? '')),
            watching: String(item['online'] ?? ''),
            popularity: String(item['online'] ?? ''),
            audienceMetricType: 'popularity',
            liveStatus: protocol_1.LiveStatus.live,
            status: true,
        });
    }
    return items.filter((room) => room.roomId !== '');
}
/** getCategoryRooms 用的 w_webid（房间分区列表签名参数），模块级缓存。 */
async function getAccessId() {
    if (accessId !== '')
        return accessId;
    const res = await (0, upstream_1.upstream)('https://live.bilibili.com/lol', { headers: await getHeader() });
    const id = /"access_id":"(.*?)"/.exec(res.text)?.[1]?.replaceAll('\\', '') ?? '';
    accessId = id;
    return accessId;
}
function buildSearchUrl(searchType) {
    return 'https://api.bilibili.com/x/web-interface/search/type?context=&search_type=' + searchType + '&cover_type=user_cover';
}
const SEARCH_COMMON_PARAMS = {
    order: '',
    keyword: '',
    category_id: '',
    __refresh__: '',
    _extra: '',
    highlight: 0,
    single_column: 0,
    page: 1,
};
class BiliBiliSite {
    async getCategories(_page, _pageSize) {
        const result = await getJson('https://api.live.bilibili.com/room/v1/Area/getList', { need_entrance: 1, parent_id: 0 }, await getHeader());
        const categories = [];
        for (const item of result['data'] ?? []) {
            const subs = [];
            for (const subItem of item['list'] ?? []) {
                subs.push({
                    platform: 'bilibili',
                    areaType: String(subItem['parent_id'] ?? ''),
                    typeName: String(subItem['parent_name'] ?? ''),
                    areaId: String(subItem['id'] ?? ''),
                    areaName: String(subItem['name'] ?? ''),
                    areaPic: `${String(subItem['pic'] ?? '')}@100w.png`,
                    shortName: '',
                });
            }
            categories.push({ id: String(item['id'] ?? ''), name: String(item['name'] ?? ''), children: subs });
        }
        return categories;
    }
    async getCategoryRooms(cateId, typeName, page, _pageSize) {
        const baseUrl = 'https://api.live.bilibili.com/xlive/web-interface/v1/second/getList';
        // Dart 的 LiveArea 同时带 areaType(parent_id) 与 areaId；HTTP 路由只传 cateId，
        // 这里从分区表反查 parent_id。
        let areaType = '';
        try {
            const categories = await this.getCategories(1, 20);
            const found = categories.flatMap((c) => c.children).find((a) => a.areaId === cateId || a.areaName === typeName);
            if (found)
                areaType = found.areaType;
        }
        catch {
            // 反查失败则不带 parent_area_id（接口可能仍按 area_id 返回）
        }
        const url = `${baseUrl}?platform=web&parent_area_id=${areaType}&area_id=${cateId}&sort_type=&page=${page}&w_webid=${await getAccessId()}`;
        const queryParams = await getWbiSign(url);
        const result = await getJson(baseUrl, queryParams, await getHeader());
        if (result['code'] === -352) {
            throw new Error(`bilibili getCategoryRooms risk-controlled: ${JSON.stringify(result)}`);
        }
        const items = [];
        for (const item of result['data']?.['list'] ?? []) {
            items.push({
                ...(0, protocol_1.emptyRoom)('bilibili', String(item['roomid'] ?? '')),
                title: String(item['title'] ?? ''),
                cover: `${String(item['cover'] ?? '')}@400w.jpg`,
                nick: String(item['uname'] ?? ''),
                avatar: String(item['face'] ?? ''),
                watching: String(item['online'] ?? ''),
                popularity: String(item['online'] ?? ''),
                audienceMetricType: 'popularity',
                liveStatus: protocol_1.LiveStatus.live,
                area: String(item['area_name'] ?? ''),
                status: true,
            });
        }
        return items;
    }
    async getRecommendRooms(page, pageSize) {
        const primaryUrl = 'https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getMoreRecList';
        let primaryError;
        // webMain 是当前匿名推荐源（无需 WBI key），失败重试一次。
        for (let attempt = 0; attempt < 2; attempt++) {
            try {
                const result = await getJson(primaryUrl, { platform: 'web', page }, await getHeader());
                return parseRecommendRooms(result);
            }
            catch (error) {
                primaryError = error;
                if (attempt === 0)
                    await new Promise((r) => setTimeout(r, 180));
            }
        }
        // 有界兜底：旧匿名 API（pageSize 上限 30，字段一致）。
        try {
            const result = await getJson('https://api.live.bilibili.com/room/v1/Area/getListByAreaID', {
                areaId: 0,
                parent_area_id: 0,
                sort: 'online',
                pageSize: Math.min(Math.max(pageSize, 1), 30),
                page,
            }, await getHeader());
            return parseRecommendRooms(result);
        }
        catch (fallbackError) {
            throw new Error(`Bilibili recommend failed: primary=${String(primaryError)}; fallback=${String(fallbackError)}`);
        }
    }
    async searchRooms(keyword, page, _pageSize) {
        const result = await getJson(buildSearchUrl('live'), { ...SEARCH_COMMON_PARAMS, keyword, page }, await getHeader());
        const items = [];
        const queryList = result['data']?.['result']?.['live_room'] ?? [];
        for (const item of queryList ?? []) {
            const title = String(item['title'] ?? '').replace(/<.*?em.*?>/g, ''); // 移除 <em></em> 高亮标签
            const live = (Number.parseInt(String(item['live_status'] ?? ''), 10) || 0) === 1;
            items.push({
                ...(0, protocol_1.emptyRoom)('bilibili', String(item['roomid'] ?? '')),
                title,
                cover: `https:${String(item['cover'] ?? '')}@400w.jpg`,
                nick: String(item['uname'] ?? ''),
                watching: String(item['online'] ?? ''),
                popularity: String(item['online'] ?? ''),
                followers: item['attentions'] != null ? String(item['attentions']) : '',
                audienceMetricType: 'popularity',
                liveStatus: live ? protocol_1.LiveStatus.live : protocol_1.LiveStatus.offline,
                area: String(item['cate_name'] ?? ''),
                status: live,
                avatar: `https:${String(item['uface'] ?? '')}@400w.jpg`,
            });
        }
        return items;
    }
    async searchAnchors(keyword, page, _pageSize) {
        const result = await getJson(buildSearchUrl('live_user'), { ...SEARCH_COMMON_PARAMS, keyword, page }, await getHeader());
        const items = [];
        for (const item of result['data']?.['result'] ?? []) {
            const uname = String(item['uname'] ?? '').replace(/<.*?em.*?>/g, ''); // 移除 <em></em> 高亮标签
            items.push({
                roomId: String(item['roomid'] ?? ''),
                title: '',
                nick: uname,
                avatar: `https:${String(item['uface'] ?? '')}@400w.jpg`,
                cover: '',
                platform: 'bilibili',
                liveStatus: item['is_live'] ? protocol_1.LiveStatus.live : protocol_1.LiveStatus.offline,
            });
        }
        return items;
    }
    async getRoomDetail(roomId) {
        const roomInfo = await getRoomInfo(roomId);
        const realRoomId = String(roomInfo['room_info']?.['room_id'] ?? '');
        const realRoomIdNum = Number.parseInt(realRoomId, 10) || 0;
        // 弹幕握手：单次快速发现，失败退回默认参数（websocket 层按需刷新凭据）。
        let danmakuData;
        try {
            danmakuData = await discoverDanmaku(realRoomIdNum, 1);
        }
        catch {
            danmakuData = defaultDanmakuArgs(realRoomIdNum);
        }
        // 开播时间：room_init 接口（需校验 code，风控时 data 为 null）。
        let biliLiveTime = 0;
        try {
            const roomInit = await getJson('https://api.live.bilibili.com/room/v1/Room/room_init', { id: roomId }, await getHeader());
            if ((Number.parseInt(String(roomInit?.['code'] ?? -1), 10) || -1) === 0) {
                biliLiveTime = Number.parseInt(String(roomInit?.['data']?.['live_time'] ?? 0), 10) || 0;
            }
        }
        catch {
            // 开播时间获取失败不影响房间详情
        }
        // 粉丝数：relation_info 偶尔随风控缺失，退回房间页 HTML 同字段。
        let followers = parseFollowersFromRoomInfo(roomInfo);
        if (followers === '' || followers === '0') {
            followers = (await fetchFollowersFromRoomPage(realRoomId)) ?? followers;
        }
        const live = (Number.parseInt(String(roomInfo['room_info']?.['live_status'] ?? 0), 10) || 0) === 1;
        return {
            ...(0, protocol_1.emptyRoom)('bilibili', roomId),
            title: String(roomInfo['room_info']?.['title'] ?? ''),
            cover: String(roomInfo['room_info']?.['cover'] ?? ''),
            nick: String(roomInfo['anchor_info']?.['base_info']?.['uname'] ?? ''),
            avatar: `${String(roomInfo['anchor_info']?.['base_info']?.['face'] ?? '')}@100w.jpg`,
            watching: String(roomInfo['room_info']?.['online'] ?? ''),
            popularity: String(roomInfo['room_info']?.['online'] ?? ''),
            audienceMetricType: 'popularity',
            area: String(roomInfo['room_info']?.['area_name'] ?? ''),
            status: live,
            liveStatus: live ? protocol_1.LiveStatus.live : protocol_1.LiveStatus.offline,
            liveStartTime: biliLiveTime > 0 ? biliLiveTime * 1000 : null,
            link: `https://live.bilibili.com/${roomId}`,
            introduction: String(roomInfo['room_info']?.['description'] ?? ''),
            notice: '',
            followers,
            danmakuData,
        };
    }
    async getPlayQualites(roomId) {
        const result = await getJson('https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo', { room_id: roomId, protocol: '0,1', format: '0,1,2', codec: '0,1', platform: 'html5', dolby: 5 }, await getHeader());
        const qualitiesMap = new Map();
        for (const item of result['data']?.['playurl_info']?.['playurl']?.['g_qn_desc'] ?? []) {
            qualitiesMap.set(Number.parseInt(String(item['qn'] ?? 0), 10) || 0, String(item['desc'] ?? ''));
        }
        const qualities = [];
        const acceptQn = result['data']?.['playurl_info']?.['playurl']?.['stream']?.[0]?.['format']?.[0]?.['codec']?.[0]?.['accept_qn'] ?? [];
        let sort = 0;
        for (const item of acceptQn) {
            const qn = Number(item);
            qualities.push({ quality: qualitiesMap.get(qn) ?? '未知清晰度', data: qn, sort: sort++ });
        }
        return qualities;
    }
    async getPlayUrls(roomId, quality) {
        const header = await getHeader();
        const baseUrl = 'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo';
        const baseParams = { room_id: roomId, protocol: '0,1', format: '0,1,2', codec: '0,1', platform: 'html5', dolby: 5 };
        // 路由传回的是 quality 名称（Dart 里 quality.data 为 qn），先反查 qn。
        const descResult = await getJson(baseUrl, { ...baseParams }, header);
        const qualitiesMap = new Map();
        for (const item of descResult['data']?.['playurl_info']?.['playurl']?.['g_qn_desc'] ?? []) {
            qualitiesMap.set(String(item['desc'] ?? ''), Number.parseInt(String(item['qn'] ?? 0), 10) || 0);
        }
        let qn = qualitiesMap.get(quality);
        if (qn === undefined && /^\d+$/.test(quality)) {
            qn = Number.parseInt(quality, 10);
        }
        if (qn === undefined) {
            throw new Error(`bilibili unknown quality: ${quality}`);
        }
        const result = await getJson(baseUrl, { ...baseParams, qn }, header);
        // 展开 协议(stream)→格式(format)→编码(codec)→CDN(host) 全部组合。
        const entries = [];
        const streamList = result['data']?.['playurl_info']?.['playurl']?.['stream'] ?? [];
        for (const streamItem of streamList) {
            for (const formatItem of streamItem['format'] ?? []) {
                const format = String(formatItem['format_name'] ?? '').toLowerCase();
                for (const codecItem of formatItem['codec'] ?? []) {
                    const baseUrlStr = String(codecItem['base_url'] ?? '');
                    const codec = String(codecItem['codec_name'] ?? '').toLowerCase();
                    for (const urlItem of codecItem['url_info'] ?? []) {
                        const host = String(urlItem['host'] ?? '');
                        entries.push({ url: `${host}${baseUrlStr}${urlItem['extra'] ?? ''}`, codec, host, format });
                    }
                }
            }
        }
        // 后端不做 Socket 测速（CdnSpeedTest 跳过，latency 恒为空），保留 Dart 的排序规则；
        // preferHEVC 默认 false（lib/common/services/settings/player_settings_controller.dart:41）。
        const preferCodec = 'avc';
        const rank = (e) => {
            if (e.url.includes('mcdn'))
                return 4; // P2P 回源节点一律沉底
            if (e.codec === 'hevc' && e.format === 'flv')
                return 2; // HEVC-flv 拿不到视频轨，沉到 ts/fmp4 之后
            if (e.codec !== '' && e.codec !== preferCodec)
                return 1;
            return 0;
        };
        entries.sort((a, b) => rank(a) - rank(b));
        return entries.map((e) => e.url);
    }
    async getLiveStatus(roomId) {
        const result = await getJson('https://api.live.bilibili.com/room/v1/Room/get_info', { room_id: roomId }, await getHeader());
        return (Number.parseInt(String(result['data']?.['live_status'] ?? 0), 10) || 0) === 1;
    }
    async sendDanmaku(roomId, message) {
        try {
            const cookie = (0, cookies_1.getCookie)('bilibili');
            const csrf = /bili_jct=([^;]+)/.exec(cookie)?.[1] ?? '';
            if (csrf === '') {
                return [false, '请先在设置中登录B站账号'];
            }
            const sendUrl = 'https://api.live.bilibili.com/msg/send';
            const queryParams = await getWbiSign(`${sendUrl}?web_location=444.8`);
            const qs = new URLSearchParams(queryParams).toString();
            const form = {
                bubble: '0',
                msg: message,
                color: '16777215',
                mode: '1',
                room_type: '0',
                jumpfrom: '0',
                reply_mid: '0',
                reply_attr: '0',
                replay_dmid: '',
                statistics: '{"appId":100,"platform":5}',
                reply_type: '0',
                reply_uname: '',
                fontsize: '25',
                rnd: String(Math.floor(Date.now() / 1000)),
                roomid: roomId,
                csrf,
                csrf_token: csrf,
            };
            const res = await (0, upstream_1.upstream)(`${sendUrl}?${qs}`, {
                method: 'POST',
                body: new URLSearchParams(form).toString(),
                headers: {
                    'content-type': 'application/x-www-form-urlencoded',
                    ...(await getHeader()),
                },
            });
            const result = JSON.parse(res.text);
            if (result['code'] === 0) {
                return [true, '发送成功'];
            }
            return [false, String(result['message'] ?? `发送失败（code=${result['code']}）`)];
        }
        catch (e) {
            return [false, `发送失败：${String(e)}`];
        }
    }
}
(0, index_1.registerSite)('bilibili', new BiliBiliSite());
