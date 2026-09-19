"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * douyu 平台 API 聚合（移植自 lib/core/site/douyu_site.dart）。
 * 取流签名改由 Node vm 执行上游原版 JS（sign/douyu.ts，替代 QuickJS）；
 * cookie 改用 auth.getCookie('douyu')（斗鱼主流程无需登录 cookie）。
 */
const index_1 = require("./index");
const protocol_1 = require("../protocol");
const upstream_1 = require("../upstream");
const douyu_1 = require("../sign/douyu");
/** Dart 里写死的 Edge UA（betard/homeH5Enc/getH5Play 共用）。 */
const K_DOUYU_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43';
/** 搜索接口用的是 .51 版本号。 */
const K_DOUYU_SEARCH_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51';
const K_GET_H5_PLAY_EXTRA = '&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0';
function douyuReferer(roomId) {
    return { referer: `https://www.douyu.com/${roomId}`, 'user-agent': K_DOUYU_UA };
}
/** dio getJson 等价：URL + query 参数，JSON 解析。 */
async function getJson(url, params, header = {}) {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(params))
        qs.set(k, String(v));
    const query = qs.toString();
    return (0, upstream_1.upstreamJson)(query ? `${url}?${query}` : url, { headers: header });
}
/** dio postJson(formUrlEncoded: true) 等价：body 为原始 form 串。 */
async function postFormJson(url, body, header = {}) {
    const res = await (0, upstream_1.upstream)(url, {
        method: 'POST',
        body,
        headers: { 'content-type': 'application/x-www-form-urlencoded', ...header },
    });
    if (res.status >= 400)
        throw new Error(`upstream ${res.status} for ${url}`);
    return JSON.parse(res.text);
}
/** HtmlUnescape().convert 等价：解码 HTML 实体（rtmp_live 里常见 &#39; 等）。 */
function htmlUnescape(input) {
    const named = {
        amp: '&',
        lt: '<',
        gt: '>',
        quot: '"',
        apos: "'",
        nbsp: ' ',
        nbspU: '\u00a0',
    };
    return input.replace(/&(#[xX]?[0-9a-fA-F]+|[a-zA-Z]+);/g, (match, code) => {
        if (code.startsWith('#')) {
            if (code.length > 1 && (code[1] === 'x' || code[1] === 'X')) {
                const parsed = Number.parseInt(code.slice(2), 16);
                return Number.isNaN(parsed) ? match : String.fromCodePoint(parsed);
            }
            const parsed = Number.parseInt(code.slice(1), 10);
            return Number.isNaN(parsed) ? match : String.fromCodePoint(parsed);
        }
        return named[code] ?? match;
    });
}
/** 生成指定长度的16进制随机字符串（搜索接口的 dy_did/acf_did）。 */
function generateRandomHexString(length) {
    let out = '';
    while (out.length < length) {
        out += Math.floor(Math.random() * 16).toString(16);
    }
    return out.substring(0, length);
}
/**
 * 拉取 homeH5Enc 返回的加密 JS 并在 vm 里执行得到签名串。
 * 对应 Dart: DouyuSign.getSign(crptext, roomId)（LiveRoom.data 的内容）。
 */
async function getDouyuSign(roomId) {
    const res = await (0, upstream_1.upstream)(`https://www.douyu.com/swf_api/homeH5Enc?rids=${roomId}`, {
        headers: douyuReferer(roomId),
    });
    if (res.status >= 400)
        throw new Error(`upstream ${res.status} for swf_api/homeH5Enc`);
    const jsEncResult = JSON.parse(res.text);
    const crptext = jsEncResult?.['data']?.[`room${roomId}`];
    if (crptext == null || String(crptext) === '') {
        throw new Error(`douyu homeH5Enc returned empty enc for room ${roomId}`);
    }
    return (0, douyu_1.evalDouyuSign)(String(crptext), roomId);
}
/** 主播卡片接口的粉丝数（betard 不含粉丝数，免签名免登录）。 */
async function fetchAnchorFans(roomId) {
    try {
        const result = await getJson('https://www.douyu.com/wgapi/livenc/liveweb/getAnchorNewCard', { rid: roomId, client_sys: 'web' }, douyuReferer(roomId));
        const fans = result?.['data']?.['roomInfo']?.['fansNum'];
        return fans != null ? String(fans) : '';
    }
    catch {
        return '';
    }
}
/** scdn 开头的 CDN 排到最后（对应 Dart getPlayQualites 里的 sort）。 */
function sortCdns(cdns) {
    return cdns.sort((a, b) => {
        if (a.startsWith('scdn') && !b.startsWith('scdn'))
            return 1;
        if (!a.startsWith('scdn') && b.startsWith('scdn'))
            return -1;
        return 0;
    });
}
class DouyuSite {
    async getCategories(_page, _pageSize) {
        const result = await getJson('https://m.douyu.com/api/cate/list', {});
        const subCateList = result['data']?.['cate2Info'] ?? [];
        const categories = [];
        for (const item of result['data']?.['cate1Info'] ?? []) {
            const cate1Id = String(item['cate1Id'] ?? '');
            const cate1Name = String(item['cate1Name'] ?? '');
            const subCategories = subCateList
                .filter((x) => String(x['cate1Id']) === cate1Id)
                .map((element) => ({
                platform: 'douyu',
                areaType: cate1Id,
                typeName: cate1Name,
                areaId: String(element['cate2Id'] ?? ''),
                areaName: String(element['cate2Name'] ?? ''),
                areaPic: String(element['icon'] ?? ''),
                shortName: '',
            }));
            categories.push({ id: cate1Id, name: cate1Name, children: subCategories });
        }
        // 根据ID排序
        categories.sort((a, b) => Number.parseInt(a.id, 10) - Number.parseInt(b.id, 10));
        return categories;
    }
    async getCategoryRooms(cateId, _typeName, page, _pageSize) {
        const result = await getJson(`https://www.douyu.com/gapi/rkc/directory/mixList/2_${cateId}/${page}`, {});
        const items = [];
        for (const item of result['data']?.['rl'] ?? []) {
            if (item['type'] !== 1)
                continue;
            items.push({
                ...(0, protocol_1.emptyRoom)('douyu', String(item['rid'] ?? '')),
                cover: String(item['rs16'] ?? ''),
                watching: String(item['ol'] ?? ''),
                popularity: String(item['ol'] ?? ''),
                audienceMetricType: 'popularity',
                title: String(item['rn'] ?? ''),
                nick: String(item['nn'] ?? ''),
                area: String(item['c2name'] ?? ''),
                liveStatus: protocol_1.LiveStatus.live,
                avatar: String(item['av'] ?? '') !== '' ? `https://apic.douyucdn.cn/upload/${item['av']}_middle.jpg` : '',
                status: true,
            });
        }
        return items;
    }
    async getRecommendRooms(page, _pageSize) {
        const result = await getJson(`https://www.douyu.com/japi/weblist/apinc/allpage/6/${page}`, {});
        const items = [];
        for (const item of result['data']?.['rl'] ?? []) {
            if (item['type'] !== 1)
                continue;
            items.push({
                ...(0, protocol_1.emptyRoom)('douyu', String(item['rid'] ?? '')),
                cover: String(item['rs16'] ?? ''),
                watching: String(item['ol'] ?? ''),
                popularity: String(item['ol'] ?? ''),
                audienceMetricType: 'popularity',
                title: String(item['rn'] ?? ''),
                nick: String(item['nn'] ?? ''),
                area: String(item['c2name'] ?? ''),
                avatar: item['av'] != null ? String(item['av']) : '',
                status: true,
                liveStatus: protocol_1.LiveStatus.live,
            });
        }
        return items;
    }
    async searchRooms(keyword, page, _pageSize) {
        const did = generateRandomHexString(32);
        const result = await getJson('https://www.douyu.com/japi/search/api/searchShow', { kw: keyword, page, pageSize: 20 }, {
            'user-agent': K_DOUYU_SEARCH_UA,
            referer: 'https://www.douyu.com/search/',
            cookie: `dy_did=${did};acf_did=${did}`,
        });
        if (result['error'] !== 0) {
            throw new Error(String(result['msg'] ?? `douyu search error ${result['error']}`));
        }
        const items = [];
        for (const item of result['data']?.['relateShow'] ?? []) {
            const isLive = (Number.parseInt(String(item['isLive'] ?? ''), 10) || 0) === 1;
            const roomType = Number.parseInt(String(item['roomType'] ?? ''), 10) || 0;
            items.push({
                ...(0, protocol_1.emptyRoom)('douyu', String(item['rid'] ?? '')),
                title: String(item['roomName'] ?? ''),
                cover: String(item['roomSrc'] ?? ''),
                area: String(item['cateName'] ?? ''),
                avatar: String(item['avatar'] ?? ''),
                liveStatus: isLive && roomType === 0 ? protocol_1.LiveStatus.live : protocol_1.LiveStatus.offline,
                status: isLive && roomType === 0,
                nick: String(item['nickName'] ?? ''),
                watching: String(item['hot'] ?? ''),
                popularity: String(item['hot'] ?? ''),
                audienceMetricType: 'popularity',
            });
        }
        return items;
    }
    async searchAnchors(keyword, page, _pageSize) {
        const did = generateRandomHexString(32);
        const result = await getJson('https://www.douyu.com/japi/search/api/searchUser', { kw: keyword, page, pageSize: 20, filterType: 1 }, {
            'user-agent': K_DOUYU_SEARCH_UA,
            referer: 'https://www.douyu.com/search/',
            cookie: `dy_did=${did};acf_did=${did}`,
        });
        const items = [];
        for (const item of result['data']?.['relateUser'] ?? []) {
            const anchor = item['anchorInfo'] ?? {};
            const isLive = (Number.parseInt(String(anchor['isLive'] ?? ''), 10) || 0) === 1;
            const roomType = Number.parseInt(String(anchor['roomType'] ?? ''), 10) || 0;
            items.push({
                roomId: String(anchor['rid'] ?? ''),
                title: '',
                nick: String(anchor['nickName'] ?? ''),
                avatar: String(anchor['avatar'] ?? ''),
                cover: '',
                platform: 'douyu',
                liveStatus: isLive && roomType === 0 ? protocol_1.LiveStatus.live : protocol_1.LiveStatus.offline,
            });
        }
        return items;
    }
    async getRoomDetail(roomId) {
        const result = await getJson(`https://www.douyu.com/betard/${roomId}`, {}, douyuReferer(roomId));
        const roomInfo = result['room'];
        // 完整详情：弹幕签名（homeH5Enc）与主播粉丝数并行获取。
        const [fans, crptext] = await Promise.all([
            fetchAnchorFans(roomId),
            (async () => {
                const res = await (0, upstream_1.upstream)(`https://www.douyu.com/swf_api/homeH5Enc?rids=${roomId}`, {
                    headers: douyuReferer(roomId),
                });
                if (res.status >= 400)
                    throw new Error(`upstream ${res.status} for swf_api/homeH5Enc`);
                return String(JSON.parse(res.text)?.['data']?.[`room${roomId}`] ?? '');
            })(),
        ]);
        // 斗鱼开播时间为 show_time（秒级时间戳）
        const showTimeRaw = roomInfo['show_time'];
        const douyuLiveTime = typeof showTimeRaw === 'number'
            ? Math.trunc(showTimeRaw)
            : Number.parseInt(String(showTimeRaw ?? ''), 10) || 0;
        const realRoomId = String(roomInfo['room_id'] ?? roomId);
        const live = roomInfo['show_status'] === 1;
        return {
            ...(0, protocol_1.emptyRoom)('douyu', roomId),
            cover: String(roomInfo['room_pic'] ?? ''),
            watching: String(roomInfo['room_biz_all']?.['hot'] ?? ''),
            popularity: String(roomInfo['room_biz_all']?.['hot'] ?? ''),
            audienceMetricType: 'popularity',
            title: String(roomInfo['room_name'] ?? ''),
            nick: String(roomInfo['owner_name'] ?? ''),
            avatar: String(roomInfo['owner_avatar'] ?? ''),
            introduction: String(roomInfo['show_details'] ?? ''),
            area: roomInfo['second_lvl_name'] != null ? String(roomInfo['second_lvl_name']) : '',
            followers: fans,
            notice: '',
            liveStatus: live ? protocol_1.LiveStatus.live : protocol_1.LiveStatus.offline,
            status: live,
            liveStartTime: douyuLiveTime > 0 ? douyuLiveTime * 1000 : null,
            danmakuData: realRoomId,
            // LiveRoom.data = 取流签名串（getH5Play 的 body 前缀）
            data: crptext === '' ? undefined : await (0, douyu_1.evalDouyuSign)(crptext, realRoomId),
            link: `https://www.douyu.com/${roomId}`,
            isRecord: roomInfo['videoLoop'] === 1,
        };
    }
    async getPlayQualites(roomId) {
        const sign = await getDouyuSign(roomId);
        // Dart 从 detail.data 取签名；后端无状态，这里按 roomId 重新拉签名。
        const result = await postFormJson(`https://www.douyu.com/lapi/live/getH5Play/${roomId}`, sign + K_GET_H5_PLAY_EXTRA);
        if (result?.['error'] !== 0) {
            throw new Error(`douyu getH5Play(qualities) error=${result?.['error']} msg=${result?.['msg']}`);
        }
        const cdns = sortCdns((result['data']?.['cdnsWithName'] ?? []).map((item) => String(item['cdn'] ?? '')));
        const qualities = [];
        let sort = 0;
        for (const item of result['data']?.['multirates'] ?? []) {
            const data = { rate: Number(item['rate']), cdns };
            qualities.push({ quality: String(item['name'] ?? ''), data, sort: sort++ });
        }
        return qualities;
    }
    async getPlayUrls(roomId, quality) {
        // detail.data 是取流签名；后端无状态，按 roomId 重新拉签名并重取 CDN 列表。
        const sign = await getDouyuSign(roomId);
        const result = await postFormJson(`https://www.douyu.com/lapi/live/getH5Play/${roomId}`, sign + K_GET_H5_PLAY_EXTRA);
        if (result?.['error'] !== 0) {
            throw new Error(`douyu getH5Play(cdns) error=${result?.['error']} msg=${result?.['msg']}`);
        }
        const cdns = sortCdns((result['data']?.['cdnsWithName'] ?? []).map((item) => String(item['cdn'] ?? '')));
        const multirates = result['data']?.['multirates'] ?? [];
        const matched = multirates.find((item) => String(item['name'] ?? '') === quality);
        let rate;
        if (matched) {
            rate = Number(matched['rate']);
        }
        else if (/^-?\d+$/.test(quality)) {
            rate = Number.parseInt(quality, 10);
        }
        else {
            throw new Error(`douyu unknown quality: ${quality}`);
        }
        const urls = [];
        for (const cdn of cdns) {
            const url = await this.getPlayUrl(roomId, sign, rate, cdn);
            if (url !== '') {
                urls.push(url);
            }
        }
        return urls;
    }
    async getPlayUrl(roomId, args, rate, cdn) {
        const result = await postFormJson(`https://www.douyu.com/lapi/live/getH5Play/${roomId}`, `${args}&cdn=${cdn}&rate=${rate}`, douyuReferer(roomId));
        if (result?.['error'] !== 0 || result?.['data']?.['rtmp_url'] == null) {
            return '';
        }
        return `${result['data']['rtmp_url']}/${htmlUnescape(String(result['data']['rtmp_live'] ?? ''))}`;
    }
    async getLiveStatus(roomId) {
        const detail = await this.getRoomDetail(roomId);
        return detail.status;
    }
    async sendDanmaku(_roomId, _message) {
        return [false, '斗鱼暂不支持发送弹幕'];
    }
}
(0, index_1.registerSite)('douyu', new DouyuSite());
