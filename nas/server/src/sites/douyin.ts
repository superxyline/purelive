/**
 * douyin 平台 API 聚合（移植自 lib/core/site/douyin_site.dart）。
 * - a_bogus 签名由 sign/douyin.ts 的 evalDouyinAbogus（Node vm 执行上游原版 JS）提供。
 * - 匿名 cookie（ttwid/UIFID_TEMP）按 Dart _fetchAnonymousCookie 捕获并进程内缓存。
 * - HTML 回退（Dart _getRoomDetailByWebRidHtml）依赖 __ac_nonce 风控链路，Node 侧
 *   不可靠，enter 接口失败时直接上抛。
 * - 弹幕参数：danmakuData = {webRid, roomId, userId}。
 */
import { registerSite } from './index';
import {
  emptyRoom,
  LiveStatus,
  type LiveAnchorItemJson,
  type LiveCategoryJson,
  type LivePlayQualityJson,
  type LiveRoomJson,
} from '../protocol';
import { upstream, upstreamJson } from '../upstream';
import { getCookie, setCookie } from '../auth/cookies';
import { evalDouyinAbogus } from '../sign/douyin';
import type { Site } from './types';

/** 使用 QQBrowser User-Agent（参考 DouyinLiveRecorder）。 */
export const K_DOUYIN_UA =
  'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400';
export const K_DOUYIN_REFERER = 'https://live.douyin.com';
const K_DOUYIN_AUTHORITY = 'live.douyin.com';

function baseHeaders(): Record<string, string> {
  return {
    authority: K_DOUYIN_AUTHORITY,
    referer: K_DOUYIN_REFERER,
    'user-agent': K_DOUYIN_UA,
  };
}

let cachedCookie = '';
let anonymousCookiePending: Promise<string> | null = null;

function configuredCookie(): string {
  return getCookie('douyin').trim();
}

/** Dart getRequestHeaders：登录 cookie 优先，否则抓匿名 ttwid。 */
async function getRequestHeaders(): Promise<Record<string, string>> {
  const configured = configuredCookie();
  if (configured !== '') {
    cachedCookie = configured;
    return { ...baseHeaders(), cookie: configured };
  }
  if (cachedCookie !== '') {
    return { ...baseHeaders(), cookie: cachedCookie };
  }
  try {
    anonymousCookiePending ??= fetchAnonymousCookie();
    const anonymous = await anonymousCookiePending;
    anonymousCookiePending = null;
    if (anonymous !== '') {
      cachedCookie = anonymous;
      setCookie('douyin', anonymous);
      return { ...baseHeaders(), cookie: anonymous };
    }
  } catch {
    anonymousCookiePending = null;
  }
  return baseHeaders();
}

/** Dart _fetchAnonymousCookie：live.douyin.com 首页 Set-Cookie 里取 ttwid/UIFID_TEMP。 */
async function fetchAnonymousCookie(): Promise<string> {
  const res = await upstream('https://live.douyin.com/?from_nav=1', { headers: baseHeaders() });
  const pairs: string[] = [];
  for (const value of res.setCookies) {
    const pair = value.split(';')[0].trim();
    if (pair.startsWith('ttwid=') || pair.startsWith('UIFID_TEMP=')) {
      pairs.push(pair);
    }
  }
  return pairs.join('; ');
}

/** 生成随机数字串（Dart generateRandomNumber）。 */
function generateRandomNumber(length: number): string {
  let out = '';
  for (let i = 0; i < length; i++) out += Math.floor(Math.random() * 10).toString();
  return out;
}

/** Dart extractCategoryDataJson：从首页 HTML 抠 categoryData 平衡大括号片段。 */
function extractCategoryDataJson(source: string): string {
  const startPattern = '{\\"pathname\\":\\"/\\",\\"categoryData\\":';
  const startIndex = source.indexOf(startPattern);
  if (startIndex === -1) return '';
  let openBraces = 0;
  let foundFirstBrace = false;
  for (let i = startIndex; i < source.length; i++) {
    if (source[i] === '{') {
      openBraces++;
      foundFirstBrace = true;
    } else if (source[i] === '}') {
      openBraces--;
    }
    if (foundFirstBrace && openBraces === 0) {
      const rawData = source.substring(startIndex, i + 1);
      return rawData.split('\\"').join('"').split('\\\\').join('\\');
    }
  }
  return '';
}

/** a_bogus 签名 URL（Dart DouyinSign.getAbogusUrl）。 */
async function getAbogusUrl(url: string): Promise<string> {
  return evalDouyinAbogus(url, K_DOUYIN_UA);
}

/** 从 owner.follow_info 取主播粉丝数（数字字段优先）。 */
function parseFollowersFromOwner(owner: any): string {
  if (owner == null || typeof owner !== 'object') return '';
  const followInfo = owner['follow_info'];
  if (followInfo == null || typeof followInfo !== 'object') return '';
  const value = followInfo['follower_count'] ?? followInfo['follower_count_str'];
  const text = value != null ? String(value) : '';
  return text === '0' ? '' : text;
}

/** 并发在线人数候选字段（Dart _douyinOnlineViewers，顶层字段优先）。 */
function douyinOnlineViewers(room: any): string {
  if (room == null || typeof room !== 'object') return '';
  const stats = room['room_view_stats'];
  const roomStats = room['stats'];
  const candidates: unknown[] = [
    room['user_count'],
    room['user_count_str'],
    room['online_user_count'],
    room['online_user_for_anchor'],
    stats?.['user_count'],
    stats?.['online_user_count'],
    stats?.['online_user_for_anchor'],
    roomStats?.['user_count'],
    roomStats?.['online_user_count'],
    roomStats?.['online_user_for_anchor'],
  ];
  for (const value of candidates) {
    const text = String(value ?? '').trim();
    if (parseAudienceNumber(text) > 0) return text;
  }
  return '';
}

/** LiveRoom.parseAudienceNumber：处理 "1.2万"/"3.4w"/千分位等展示串。 */
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

function asInt(value: unknown): number {
  if (typeof value === 'number') return Math.trunc(value);
  return Number.parseInt(String(value ?? ''), 10) || 0;
}

/** 房间进入接口公共 query（Dart _getRoomDataByApi / partition v2 共用前缀）。 */
function douyinBaseQuery(): Record<string, string> {
  return {
    aid: '6383',
    app_name: 'douyin_web',
    live_id: '1',
    device_platform: 'web',
    cookie_enabled: 'true',
    screen_width: '1980',
    screen_height: '1080',
    browser_language: 'zh-CN',
    browser_platform: 'Win32',
    browser_name: 'Edge',
    browser_version: '125.0.0.0',
  };
}

function qsOf(params: Record<string, string>): string {
  return new URLSearchParams(params).toString();
}

/** webcast/room/web/enter/（Dart _getRoomDataByApi），返回 data 字段。 */
async function getRoomDataByApi(webRid: string): Promise<Record<string, any>> {
  const uri =
    'https://live.douyin.com/webcast/room/web/enter/?' +
    qsOf({
      ...douyinBaseQuery(),
      enter_from: 'web_live',
      web_rid: webRid,
      room_id_str: '',
      enter_source: '',
      'Room-Enter-User-Login-Ab': '0',
      is_need_double_stream: 'false',
    });
  const requestUrl = await getAbogusUrl(uri);
  const headers = await getRequestHeaders();
  const result = await upstreamJson(requestUrl, { headers });
  return result['data'] ?? {};
}

/** reflow/info（Dart _getRoomDataByRoomId）。 */
async function getRoomDataByRoomId(roomId: string): Promise<Record<string, any>> {
  const qs = qsOf({
    type_id: '0',
    live_id: '1',
    room_id: roomId,
    sec_user_id: '',
    version_code: '99.99.99',
    app_id: '6383',
  });
  const result = await upstreamJson(`https://webcast.amemv.com/webcast/room/reflow/info/?${qs}`, {
    headers: await getRequestHeaders(),
  });
  return result ?? {};
}

/** Dart _fetchRoomExtra：reflow 补粉丝数与开播时间。 */
async function fetchRoomExtra(roomId: string): Promise<{ followers: string; startTimeSec: number }> {
  if (roomId === '') return { followers: '', startTimeSec: 0 };
  try {
    const roomData = await getRoomDataByRoomId(roomId);
    const room = roomData['data']?.['room'];
    return {
      followers: parseFollowersFromOwner(room?.['owner']),
      startTimeSec: asInt(room?.['create_time']),
    };
  } catch {
    return { followers: '', startTimeSec: 0 };
  }
}

/** 分区房间列表项 → LiveRoom（ getCategoryRooms / getRecommendRooms 共用）。 */
function listRoomFromFeedItem(item: any): LiveRoomJson {
  return {
    ...emptyRoom('douyin', String(item['web_rid'] ?? '')),
    title: String(item['room']?.['title'] ?? ''),
    cover: String(item['room']?.['cover']?.['url_list']?.[0] ?? ''),
    nick: String(item['room']?.['owner']?.['nickname'] ?? ''),
    avatar: String(item['room']?.['owner']?.['avatar_thumb']?.['url_list']?.[0] ?? ''),
    area: String(item['tag_name'] ?? ''),
    watching: String(item['room']?.['room_view_stats']?.['display_value'] ?? ''),
    totalViewers: String(item['room']?.['room_view_stats']?.['display_value'] ?? ''),
    onlineViewers: douyinOnlineViewers(item['room']),
    audienceMetricType: 'totalViewers',
    liveStatus: LiveStatus.live,
  };
}

async function fetchPartitionRooms(partitionId: string, partitionType: string, page: number, count: number): Promise<LiveRoomJson[]> {
  const uri =
    'https://live.douyin.com/webcast/web/partition/detail/room/v2/?' +
    qsOf({
      ...douyinBaseQuery(),
      language: 'zh-CN',
      enter_from: 'link_share',
      browser_online: 'true',
      count: String(count),
      offset: String((page - 1) * count),
      partition: partitionId,
      partition_type: partitionType,
      req_from: '2',
    });
  const requestUrl = await getAbogusUrl(uri);
  const result = await upstreamJson(requestUrl, { headers: await getRequestHeaders() });
  return ((result['data']?.['data'] ?? []) as any[]).map(listRoomFromFeedItem);
}

class DouyinSite implements Site {
  async getCategories(_page: number, _pageSize: number): Promise<LiveCategoryJson[]> {
    const res = await upstream('https://live.douyin.com/?from_nav=1', {
      headers: await getRequestHeaders(),
    });
    const extracted = extractCategoryDataJson(res.text);
    const renderDataJson = JSON.parse(extracted) as Record<string, any>;
    const data = renderDataJson['categoryData'] ?? [];
    const categories: LiveCategoryJson[] = [];
    for (const item of data) {
      const id = `${item['partition']['id_str']},${item['partition']['type']}`;
      const name = String(item['partition']['title'] ?? '');
      const subs: LiveCategoryJson['children'] = [];
      for (const subItem of item['sub_partition'] ?? []) {
        subs.push({
          platform: 'douyin',
          areaId: `${subItem['partition']['id_str']},${subItem['partition']['type']}`,
          typeName: String(item['partition']['title'] ?? ''),
          areaType: id,
          areaName: String(subItem['partition']['title'] ?? ''),
          areaPic: '',
          shortName: '',
        });
      }
      // 自身分区插到子分区最前（Dart 同款）
      subs.unshift({
        platform: 'douyin',
        areaId: id,
        typeName: name,
        areaType: id,
        areaName: name,
        areaPic: '',
        shortName: '',
      });
      categories.push({ id, name, children: subs });
    }
    return categories;
  }

  async getCategoryRooms(cateId: string, _typeName: string, page: number, _pageSize: number): Promise<LiveRoomJson[]> {
    const ids = cateId.split(',');
    const partitionId = ids[0] ?? '';
    const partitionType = ids[1] ?? '';
    return fetchPartitionRooms(partitionId, partitionType, page, 15);
  }

  async getRecommendRooms(page: number, _pageSize: number): Promise<LiveRoomJson[]> {
    return fetchPartitionRooms('720', '1', page, 20);
  }

  async getRoomDetail(roomId: string): Promise<LiveRoomJson> {
    if (roomId.length <= 16) {
      return getRoomDetailByWebRid(roomId);
    }
    return getRoomDetailByRoomId(roomId);
  }

  async getPlayQualites(roomId: string): Promise<LivePlayQualityJson[]> {
    const detail = await this.getRoomDetail(roomId);
    return parseDouyinPlayQualities(detail.data);
  }

  async getPlayUrls(roomId: string, quality: string): Promise<string[]> {
    const qualities = await this.getPlayQualites(roomId);
    const matched =
      qualities.find((item) => item.quality === quality) ??
      (qualities.length > 0 ? qualities[0] : undefined);
    return matched ? (matched.data as string[]) : [];
  }

  async getLiveStatus(roomId: string): Promise<boolean> {
    const detail = await this.getRoomDetail(roomId);
    return detail.status;
  }

  async searchRooms(keyword: string, page: number, _pageSize: number): Promise<LiveRoomJson[]> {
    // Dart searchRooms 不做 a_bogus 签名（webapp 通道）
    const params: Record<string, string> = {
      device_platform: 'webapp',
      aid: '6383',
      channel: 'channel_pc_web',
      search_channel: 'aweme_live',
      keyword,
      search_source: 'switch_tab',
      query_correct_type: '1',
      is_filter_search: '0',
      from_group_id: '',
      offset: String((page - 1) * 10),
      count: '10',
      pc_client_type: '1',
      version_code: '170400',
      version_name: '17.4.0',
      cookie_enabled: 'true',
      screen_width: '1980',
      screen_height: '1080',
      browser_language: 'zh-CN',
      browser_platform: 'Win32',
      browser_name: 'Edge',
      browser_version: '125.0.0.0',
      browser_online: 'true',
      engine_name: 'Blink',
      engine_version: '125.0.0.0',
      os_name: 'Windows',
      os_version: '10',
      cpu_core_num: '12',
      device_memory: '8',
      platform: 'PC',
      downlink: '10',
      effective_type: '4g',
      round_trip_time: '100',
      webid: '7382872326016435738',
    };
    const headers = await getRequestHeaders();
    const result = await upstreamJson(`https://www.douyin.com/aweme/v1/web/live/search/?${qsOf(params)}`, {
      headers: {
        authority: 'www.douyin.com',
        accept: 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        cookie: headers['cookie'] ?? '',
        priority: 'u=1, i',
        referer: `https://www.douyin.com/search/${encodeURIComponent(keyword)}?type=live`,
        'sec-ch-ua': '"Microsoft Edge";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'user-agent': K_DOUYIN_UA,
      },
    });
    const resultText = typeof result === 'string' ? result : '';
    if (resultText === 'blocked') {
      throw new Error('抖音直播搜索被限制，请稍后再试');
    }
    const items: LiveRoomJson[] = [];
    for (const item of result['data'] ?? []) {
      const itemData = JSON.parse(String(item['lives']?.['rawdata'] ?? '{}'));
      const roomStatus = asInt(itemData['status']) === 2;
      items.push({
        ...emptyRoom('douyin', String(itemData['owner']?.['web_rid'] ?? '')),
        title: String(itemData['title'] ?? ''),
        cover: String(itemData['cover']?.['url_list']?.[0] ?? ''),
        nick: String(itemData['owner']?.['nickname'] ?? ''),
        avatar: String(itemData['owner']?.['avatar_thumb']?.['url_list']?.[0] ?? ''),
        liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
        status: roomStatus,
        watching: String(itemData['stats']?.['total_user_str'] ?? ''),
        totalViewers: String(itemData['stats']?.['total_user_str'] ?? ''),
        onlineViewers: douyinOnlineViewers(itemData),
        audienceMetricType: 'totalViewers',
      });
    }
    return items;
  }

  async searchAnchors(_keyword: string, _page: number, _pageSize: number): Promise<LiveAnchorItemJson[]> {
    throw new Error('抖音暂不支持搜索主播，请直接搜索直播间');
  }

  async sendDanmaku(_roomId: string, _message: string): Promise<[boolean, string]> {
    return [false, '抖音暂不支持发送弹幕'];
  }
}

/** LiveRoom.data（stream_url）→ 清晰度列表（Dart getPlayQualites 两分支）。 */
function parseDouyinPlayQualities(rawData: unknown): LivePlayQualityJson[] {
  const data = (rawData ?? {}) as Record<string, any>;
  const qualities: LivePlayQualityJson[] = [];
  const qualityList: any[] = data['live_core_sdk_data']?.['pull_data']?.['options']?.['qualities'] ?? [];
  const streamData = String(data['live_core_sdk_data']?.['pull_data']?.['stream_data'] ?? '');

  if (!streamData.startsWith('{')) {
    const flvList: string[] = Object.values(data['flv_pull_url'] ?? {}) as string[];
    const hlsList: string[] = Object.values(data['hls_pull_url_map'] ?? {}) as string[];
    for (const quality of qualityList) {
      const level = asInt(quality['level']);
      const urls: string[] = [];
      const flvIndex = flvList.length - level;
      if (flvIndex >= 0 && flvIndex < flvList.length) urls.push(flvList[flvIndex]);
      const hlsIndex = hlsList.length - level;
      if (hlsIndex >= 0 && hlsIndex < hlsList.length) urls.push(hlsList[hlsIndex]);
      if (urls.length > 0) {
        qualities.push({ quality: String(quality['name'] ?? ''), sort: level, data: urls });
      }
    }
  } else {
    const qualityData = (JSON.parse(streamData)['data'] ?? {}) as Record<string, any>;
    for (const quality of qualityList) {
      const urls: string[] = [];
      const sdkKey = quality['sdk_key'];
      const flvUrl = qualityData[sdkKey]?.['main']?.['flv'];
      if (flvUrl != null && flvUrl !== '') urls.push(String(flvUrl));
      const hlsUrl = qualityData[sdkKey]?.['main']?.['hls'];
      if (hlsUrl != null && hlsUrl !== '') urls.push(String(hlsUrl));
      if (urls.length > 0) {
        qualities.push({ quality: String(quality['name'] ?? ''), sort: asInt(quality['level']), data: urls });
      }
    }
  }
  qualities.sort((a, b) => b.sort - a.sort);
  return qualities;
}

/** 通过 roomId（reflow 接口，Dart getRoomDetailByRoomId）。 */
async function getRoomDetailByRoomId(roomId: string): Promise<LiveRoomJson> {
  const roomData = await getRoomDataByRoomId(roomId);
  const webRid = String(roomData['data']?.['room']?.['owner']?.['web_rid'] ?? '');
  const userUniqueId = generateRandomNumber(12);
  const room = roomData['data']?.['room'] ?? {};
  const owner = room['owner'] ?? {};
  const status = asInt(room['status']);
  // roomId 是一次性的：status=4 说明已下播，按 webRid 重新进
  if (status === 4) {
    return getRoomDetailByWebRid(webRid);
  }
  const roomStatus = status === 2;
  const headers = await getRequestHeaders();
  const startTimeSec = asInt(room['create_time']);
  void headers;
  return {
    ...emptyRoom('douyin', webRid),
    title: String(room['title'] ?? ''),
    cover: roomStatus ? String(room['cover']?.['url_list']?.[0] ?? '') : '',
    nick: String(owner['nickname'] ?? ''),
    avatar: String(owner['avatar_thumb']?.['url_list']?.[0] ?? ''),
    watching: roomStatus ? String(room['room_view_stats']?.['display_value'] ?? '') : '',
    totalViewers: roomStatus ? String(room['room_view_stats']?.['display_value'] ?? '') : '',
    onlineViewers: roomStatus ? douyinOnlineViewers(room) : '',
    audienceMetricType: 'totalViewers',
    status: roomStatus,
    liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
    liveStartTime: roomStatus && startTimeSec > 0 ? startTimeSec * 1000 : null,
    link: `https://live.douyin.com/${webRid}`,
    area: '',
    introduction: String(owner['signature'] ?? ''),
    followers: parseFollowersFromOwner(owner),
    danmakuData: { webRid, roomId, userId: userUniqueId },
    data: room['stream_url'] ?? {},
  };
}

/** 通过 WebRid（web/enter 接口，Dart _getRoomDetailByWebRidApi）。 */
async function getRoomDetailByWebRid(webRid: string): Promise<LiveRoomJson> {
  const data = await getRoomDataByApi(webRid);
  const roomData = data['data']?.[0] ?? {};
  const userData = data['user'] ?? {};
  const roomId = String(roomData['id_str'] ?? '');
  const userUniqueId = generateRandomNumber(12);
  const owner = roomData['owner'] ?? {};
  const roomStatus = asInt(roomData['status']) === 2;
  const douyinStartTime = asInt(roomData['create_time']);

  // follow_info/create_time 兜底（Dart _fetchRoomExtra）
  const extra =
    roomStatus && douyinStartTime > 0 ? { followers: '', startTimeSec: 0 } : await fetchRoomExtra(roomId);
  const startTimeSec = douyinStartTime > 0 ? douyinStartTime : extra.startTimeSec;

  return {
    ...emptyRoom('douyin', webRid),
    title: String(roomData['title'] ?? ''),
    cover: roomStatus ? String(roomData['cover']?.['url_list']?.[0] ?? '') : '',
    nick: roomStatus ? String(owner['nickname'] ?? '') : String(userData['nickname'] ?? ''),
    avatar: roomStatus
      ? String(owner['avatar_thumb']?.['url_list']?.[0] ?? '')
      : String(userData['avatar_thumb']?.['url_list']?.[0] ?? ''),
    watching: roomStatus ? String(roomData['room_view_stats']?.['display_value'] ?? '') : '',
    totalViewers: roomStatus ? String(roomData['room_view_stats']?.['display_value'] ?? '') : '',
    onlineViewers: roomStatus ? douyinOnlineViewers(roomData) : '',
    audienceMetricType: 'totalViewers',
    status: roomStatus,
    liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
    liveStartTime: roomStatus && startTimeSec > 0 ? startTimeSec * 1000 : null,
    link: `https://live.douyin.com/${webRid}`,
    area: '',
    introduction: String(owner['signature'] ?? ''),
    followers: extra.followers,
    danmakuData: { webRid, roomId, userId: userUniqueId },
    data: roomStatus ? roomData['stream_url'] ?? {} : {},
  };
}

registerSite('douyin', new DouyinSite());
export { getRequestHeaders as getDouyinRequestHeaders, parseAudienceNumber };
