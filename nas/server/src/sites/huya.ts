/**
 * huya 平台 API 聚合（移植自 lib/core/site/huya_site.dart）。
 * - 列表/搜索：cache.php 与 search.cdn.huya.com，逐字段对应。
 * - 详情：mp.huya.com profileRoom（showSecret=1）；网页回退（Dart 走隐藏 WebView）
 *   Node 侧无法复用，失败时直接返回错误房间。
 * - 取流：buildAntiCode 纯算法移植（md5 wsSecret）；Dart 的 TUP getCdnTokenInfoEx
 *   直接用 profileRoom 的 sFlvAntiCode（同构字段 fm/wsTime/fs/ctype/t）替代，绕过 TUP。
 * - 弹幕参数：danmakuData = {uid, topSid, subSid}（HuyaDanmakuArgs）。
 */
import { createHash } from 'crypto';
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
import { getCookie } from '../auth/cookies';
import type { Site } from './types';

/** 列表/详情用移动端 UA（Dart kUserAgent）。 */
const K_HUYA_MOBILE_UA =
  'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0';

function md5Hex(text: string): string {
  return createHash('md5').update(text, 'utf8').digest('hex');
}

function huyaCookie(): string {
  return getCookie('huya');
}

/** Dart getUid：yyuid cookie > streamName 前缀 > 随机兜底。 */
function getUid(cookie: string, streamName: string): number {
  if (cookie.includes('yyuid=')) {
    const match = /yyuid=(\d+)/.exec(cookie);
    if (match) return Number.parseInt(match[1], 10);
  }
  const parts = streamName.split('-');
  if (parts.length > 0) {
    const anchorUid = Number.parseInt(parts[0], 10);
    if (!Number.isNaN(anchorUid) && anchorUid > 0) return anchorUid;
  }
  return 1400000000000 + Math.floor(Math.random() * 100000000000);
}

/** Dart rotl64：低 32 位循环左移 8 位。 */
function rotl64(t: number): number {
  const low = t & 0xffffffff;
  return ((low << 8) | (low >>> 24)) & 0xffffffff;
}

function splitQuery(query: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of new URLSearchParams(query)) out[k] = v;
  return out;
}

/**
 * 构造取流 anticode（Dart buildAntiCode，python 转写同源）。
 * [antiCode] 为页面/接口返回的原始 anticode（含 fm/wsTime/fs/ctype/t）。
 */
function buildAntiCode(stream: string, presenterUid: number, antiCode: string): string {
  const mapAnti = splitQuery(antiCode);
  if (!('fm' in mapAnti)) {
    return antiCode;
  }
  const ctype = mapAnti['ctype'] ?? 'huya_pc_exe';
  const platformId = Number.parseInt(mapAnti['t'] ?? '0', 10) || 0;
  const isWap = platformId === 103;

  const seqId = presenterUid + Date.now();
  const secretHash = md5Hex(`${seqId}|${ctype}|${platformId}`);
  const convertUid = rotl64(presenterUid);
  const calcUid = isWap ? presenterUid : convertUid;
  const fm = decodeURIComponent(mapAnti['fm'] ?? '');
  const secretPrefix = Buffer.from(fm, 'base64').toString('utf8').split('_')[0];
  const wsTime = mapAnti['wsTime'] ?? '';
  const secretStr = `${secretPrefix}_${calcUid}_${stream}_${secretHash}_${wsTime}`;
  const wsSecret = md5Hex(secretStr);

  const ct = Math.trunc((Number.parseInt(wsTime, 16) + Math.random()) * 1000);
  const uuid = Math.trunc(((ct % 1e10) + Math.random()) * 1e3 * 0xffffffff);
  const parts: string[] = [
    `wsSecret=${wsSecret}`,
    `wsTime=${wsTime}`,
    `seqid=${seqId}`,
    `ctype=${ctype}`,
    'ver=1',
    `fs=${mapAnti['fs'] ?? ''}`,
    `fm=${encodeURIComponent(mapAnti['fm'] ?? '')}`,
    `t=${platformId}`,
  ];
  if (isWap) {
    parts.push(`uid=${presenterUid}`, `uuid=${uuid}`);
  } else {
    parts.push(`u=${convertUid}`);
  }
  return parts.join('&');
}

/** profileRoom 的单条流信息。 */
interface HuyaStreamInfo {
  sFlvUrl: string;
  sHlsUrl: string;
  sFlvAntiCode: string;
  sHlsAntiCode: string;
  sStreamName: string;
  sCdnType: string;
  lChannelId: number | string;
  lSubChannelId: number | string;
}

/** LiveRoom.data：HuyaUrlDataModel 的 JSON 同构。 */
export interface HuyaUrlData {
  url: string;
  uid: string;
  isXingxiu: boolean;
  lines: Array<{
    line: string;
    lineType: 'flv' | 'hls';
    flvAntiCode: string;
    hlsAntiCode: string;
    streamName: string;
    cdnType: string;
    presenterUid: number;
  }>;
  bitRates: Array<{ name: string; bitRate: number }>;
}

function asInt(value: unknown): number {
  if (typeof value === 'number') return Math.trunc(value);
  return Number.parseInt(String(value ?? ''), 10) || 0;
}

/** Dart _buildRoomFromProfileData 的移植核心：解析 data → 房间 + lines/bitRates。 */
function buildRoomFromProfileData(data: Record<string, any>, roomId: string): LiveRoomJson {
  let topSid = 0;
  let subSid = 0;
  const lines: HuyaUrlData['lines'] = [];
  const bitRates: HuyaUrlData['bitRates'] = [];

  const baseSteamInfoList: HuyaStreamInfo[] = data['stream']?.['baseSteamInfoList'] ?? [];
  const findByCdn = (cdnType: unknown): HuyaStreamInfo | undefined =>
    baseSteamInfoList.find((element) => String(element.sCdnType) === String(cdnType ?? ''));

  const pushLine = (item: any, url: string, lineType: 'flv' | 'hls') => {
    const currentStream = findByCdn(item['cdnType']);
    if (!currentStream) return;
    topSid = asInt(currentStream.lChannelId);
    subSid = asInt(currentStream.lSubChannelId);
    lines.push({
      line: url,
      lineType,
      flvAntiCode: String(currentStream.sFlvAntiCode ?? ''),
      hlsAntiCode: String(currentStream.sHlsAntiCode ?? ''),
      streamName: String(currentStream.sStreamName ?? ''),
      cdnType: String(item['sCdnType'] ?? ''),
      presenterUid: topSid,
    });
  };

  for (const item of data['stream']?.['flv']?.['multiLine'] ?? []) {
    if (String(item['url'] ?? '') !== '') pushLine(item, String(item['url']), 'flv');
  }
  for (const item of data['stream']?.['hls']?.['multiLine'] ?? []) {
    if (String(item['url'] ?? '') !== '') pushLine(item, String(item['url']), 'hls');
  }

  // 清晰度：bitRateInfo（登录态 mp）优先，否则 rateArray
  let biterates: any[] = [];
  if (data['liveData']?.['bitRateInfo'] != null) {
    try {
      biterates =
        typeof data['liveData']['bitRateInfo'] === 'string'
          ? (JSON.parse(data['liveData']['bitRateInfo']) as any[])
          : (data['liveData']['bitRateInfo'] as any[]);
    } catch {
      biterates = [];
    }
  } else {
    biterates = data['stream']?.['flv']?.['rateArray'] ?? [];
  }
  for (const item of biterates) {
    const name = String(item['sDisplayName'] ?? '');
    if (!bitRates.some((e) => e.name === name)) {
      bitRates.push({ bitRate: asInt(item['iBitRate']), name });
    }
  }

  const isXingxiu = asInt(data['liveData']?.['gid']) === 1663;
  // 上下文一致：totalCount/userCount 同为热度口径（parseRoomAudience）
  const totalCount = String(data['liveData']?.['totalCount'] ?? '').trim();
  const userCount = String(data['liveData']?.['userCount'] ?? '').trim();
  const popularity = totalCount !== '' ? totalCount : userCount;

  const liveState = String(data['liveStatus'] ?? '');
  const live = liveState === 'ON' || liveState === 'REPLAY';
  const startTimeSec = asInt(data['liveData']?.['startTime']);

  return {
    ...emptyRoom('huya', roomId),
    cover: String(data['liveData']?.['screenshot'] ?? ''),
    watching: popularity,
    popularity,
    onlineViewers: '',
    audienceMetricType: 'popularity',
    area: String(data['liveData']?.['gameFullName'] ?? ''),
    title: String(data['liveData']?.['introduction'] ?? ''),
    nick: String(data['profileInfo']?.['nick'] ?? ''),
    avatar: String(data['profileInfo']?.['avatar180'] ?? ''),
    introduction: String(data['liveData']?.['introduction'] ?? ''),
    notice: String(data['welcomeText'] ?? ''),
    followers: data['profileInfo']?.['fans'] != null ? String(data['profileInfo']['fans']) : '',
    status: live,
    liveStatus: live ? LiveStatus.live : LiveStatus.offline,
    liveStartTime: startTimeSec > 0 ? startTimeSec * 1000 : null,
    data: { url: '', uid: '', isXingxiu, lines, bitRates } satisfies HuyaUrlData,
    danmakuData: {
      uid: asInt(data['profileInfo']?.['uid']),
      topSid,
      subSid,
    },
    link: `https://www.huya.com/${roomId}`,
  };
}

/** 房间页 TT_PROFILE_INFO.fans（失败返回空串）。 */
async function fetchFansCount(roomId: string): Promise<string> {
  try {
    const res = await upstream(`https://www.huya.com/${roomId}`, {
      headers: { 'user-agent': K_HUYA_MOBILE_UA, referer: 'https://www.huya.com/' },
    });
    const match = /"fans"\s*:\s*"?(\d{2,})"?/.exec(res.text);
    return match ? match[1] : '';
  } catch {
    return '';
  }
}

function huyaListHeaders(extra: Record<string, string> = {}): Record<string, string> {
  return {
    'user-agent': K_HUYA_MOBILE_UA,
    cookie: huyaCookie(),
    ...extra,
  };
}

interface HuyaListRoomItem {
  profileRoom: unknown;
  screenshot: unknown;
  introduction: unknown;
  roomName: unknown;
  nick: unknown;
  totalCount: unknown;
  avatar180: unknown;
  gameFullName: unknown;
}

function listRoomFromItem(item: HuyaListRoomItem): LiveRoomJson {
  let cover = String(item.screenshot ?? '');
  if (!cover.includes('?')) {
    cover += '?x-oss-process=style/w338_h190&';
  }
  let title = String(item.introduction ?? '');
  if (title === '') {
    title = String(item.roomName ?? '');
  }
  return {
    ...emptyRoom('huya', String(item.profileRoom ?? '')),
    title,
    cover,
    nick: String(item.nick ?? ''),
    watching: String(item.totalCount ?? ''),
    popularity: String(item.totalCount ?? ''),
    audienceMetricType: 'popularity',
    avatar: String(item.avatar180 ?? ''),
    area: String(item.gameFullName ?? ''),
    liveStatus: LiveStatus.live,
    status: true,
  };
}

async function fetchHuyaList(
  params: Record<string, string | number>,
  extraHeaders: Record<string, string>,
): Promise<HuyaListRoomItem[]> {
  const qs = new URLSearchParams({ tagAll: '0' });
  for (const [k, v] of Object.entries(params)) qs.set(k, String(v));
  const res = await upstreamJson<{ data?: { datas?: HuyaListRoomItem[] } }>(
    `https://www.huya.com/cache.php?${qs.toString()}`,
    { headers: huyaListHeaders(extraHeaders) },
  );
  return res?.data?.datas ?? [];
}

class HuyaSite implements Site {
  async getCategories(_page: number, _pageSize: number): Promise<LiveCategoryJson[]> {
    const base = [
      { id: '1', name: '网游' },
      { id: '2', name: '单机' },
      { id: '8', name: '娱乐' },
      { id: '3', name: '手游' },
    ];
    const categories: LiveCategoryJson[] = [];
    for (const item of base) {
      const result = await upstreamJson<{ data?: any[] }>(
        `https://live.cdn.huya.com/liveconfig/game/bussLive?bussType=${item.id}`,
      );
      const children = (result['data'] ?? []).map((element) => {
        const gid = String(asInt(element['gid']));
        return {
          platform: 'huya',
          areaType: item.id,
          typeName: item.name,
          areaId: gid,
          areaName: String(element['gameFullName'] ?? ''),
          areaPic: `https://huyaimg.msstatic.com/cdnimage/game/${gid}-MS.jpg`,
          shortName: '',
        };
      });
      categories.push({ id: item.id, name: item.name, children });
    }
    return categories;
  }

  async getCategoryRooms(cateId: string, _typeName: string, page: number, _pageSize: number): Promise<LiveRoomJson[]> {
    const items = await fetchHuyaList({ m: 'LiveList', do: 'getLiveListByPage', gameId: cateId, page }, {});
    return items.map(listRoomFromItem);
  }

  async getRecommendRooms(page: number, _pageSize: number): Promise<LiveRoomJson[]> {
    const items = await fetchHuyaList(
      { m: 'LiveList', do: 'getLiveListByPage', page },
      { origin: 'https://www.huya.com', referer: 'https://www.huya.com/' },
    );
    return items.map(listRoomFromItem);
  }

  async searchRooms(keyword: string, page: number, _pageSize: number): Promise<LiveRoomJson[]> {
    const result = await this.search(keyword, 4, 20, (page - 1) * 20);
    const docs = result?.response?.['3']?.docs ?? [];
    const responseList = result?.response?.['1']?.docs ?? [];
    const items: LiveRoomJson[] = [];
    for (const item of docs) {
      let cover = String(item['game_screenshot'] ?? '');
      if (!cover.includes('?')) {
        cover += '?x-oss-process=style/w338_h190&';
      }
      let title = String(item['game_introduction'] ?? '');
      if (title === '') {
        title = String(item['game_roomName'] ?? '');
      }
      const roomId = this.findRoomId(responseList, asInt(item['uid']), asInt(item['yyid']));
      items.push({
        ...emptyRoom('huya', roomId ?? String(item['room_id'] ?? '')),
        title,
        cover,
        userId: String(item['yyid'] ?? ''),
        nick: String(item['game_nick'] ?? ''),
        area: String(item['gameName'] ?? ''),
        status: true,
        liveStatus: LiveStatus.live,
        avatar: String(item['game_imgUrl'] ?? ''),
        watching: String(item['game_total_count'] ?? ''),
        popularity: String(item['game_total_count'] ?? ''),
        audienceMetricType: 'popularity',
      });
    }
    return items;
  }

  async searchAnchors(keyword: string, page: number, pageSize: number): Promise<LiveAnchorItemJson[]> {
    const result = await this.search(keyword, 1, pageSize, (page - 1) * pageSize);
    const items: LiveAnchorItemJson[] = [];
    for (const item of result?.response?.['1']?.docs ?? []) {
      items.push({
        roomId: String(item['room_id'] ?? ''),
        avatar: String(item['game_avatarUrl180'] ?? ''),
        title: '',
        nick: String(item['game_nick'] ?? ''),
        cover: '',
        platform: 'huya',
        liveStatus: item['gameLiveOn'] ? LiveStatus.live : LiveStatus.offline,
      });
    }
    return items;
  }

  private async search(keyword: string, v: number, rows: number, start: number) {
    const qs = new URLSearchParams({
      m: 'Search',
      do: 'getSearchContent',
      q: keyword,
      uid: '0',
      v: String(v),
      typ: '-5',
      livestate: '0',
      rows: String(rows),
      start: String(start),
    });
    return upstreamJson(`https://search.cdn.huya.com/?${qs.toString()}`);
  }

  /** Dart findRoomId：response["1"] 里按 uid+yyid 找 room_id。 */
  private findRoomId(list: any[], targetUid: number, targetYyid: number): string | null {
    const match = list.find((item) => asInt(item['uid']) === targetUid && asInt(item['yyid']) === targetYyid);
    return match ? String(match['room_id']) : null;
  }

  async getRoomDetail(roomId: string): Promise<LiveRoomJson> {
    // 粉丝数在房间页 TT_PROFILE_INFO.fans，mp 接口不提供，与详情并行拉取
    const [res, fansCount] = await Promise.all([
      upstream(
        `https://mp.huya.com/cache.php?m=Live&do=profileRoom&roomid=${encodeURIComponent(roomId)}&showSecret=1`,
        {
          headers: {
            accept: '*/*',
            origin: 'https://www.huya.com',
            referer: 'https://www.huya.com/',
            'user-agent': K_HUYA_MOBILE_UA,
            cookie: huyaCookie(),
          },
        },
      ),
      fetchFansCount(roomId),
    ]);
    if (res.status >= 400) throw new Error(`huya profileRoom upstream ${res.status}`);
    const result = JSON.parse(res.text) as Record<string, any>;
    if (result['status'] === 200 && result['data']?.['stream'] != null) {
      const room = buildRoomFromProfileData(result['data'], roomId);
      if (fansCount !== '') room.followers = fansCount;
      return room;
    }
    // 网页回退（Dart 隐藏 WebView）Node 侧无对应实现：按错误房间处理
    return {
      ...emptyRoom('huya', roomId),
      status: false,
      liveStatus: LiveStatus.offline,
      link: `https://www.huya.com/${roomId}`,
    };
  }

  async getPlayQualites(roomId: string): Promise<LivePlayQualityJson[]> {
    const detail = await this.getRoomDetail(roomId);
    const urlData = (detail.data ?? {}) as HuyaUrlData;
    const bitRates = urlData.bitRates?.length
      ? urlData.bitRates
      : [
          { name: '原画', bitRate: 0 },
          { name: '高清', bitRate: 2000 },
        ];
    const qualities: LivePlayQualityJson[] = [];
    let sort = 0;
    for (const item of bitRates) {
      qualities.push({
        quality: item.name,
        data: { lines: urlData.lines ?? [], bitRate: item.bitRate },
        sort: sort++,
      });
    }
    return qualities;
  }

  async getPlayUrls(roomId: string, quality: string): Promise<string[]> {
    const qualities = await this.getPlayQualites(roomId);
    const matched = qualities.find((item) => item.quality === quality) ?? qualities[0];
    if (!matched) return [];
    const data = (matched.data ?? {}) as { lines: HuyaUrlData['lines']; bitRate: number };
    const urls: string[] = [];
    for (const line of data.lines ?? []) {
      try {
        urls.push(this.buildPlayUrl(line, data.bitRate));
      } catch {
        // 单线路失败不阻断其余线路
      }
    }
    return urls;
  }

  /** Dart getPlayUrl：anticode 改用 sFlvAntiCode/sHlsAntiCode（绕过 TUP getCdnTokenInfoEx）。 */
  private buildPlayUrl(line: HuyaUrlData['lines'][number], bitRate: number): string {
    const antiCode = buildAntiCode(
      line.streamName,
      line.presenterUid,
      line.lineType === 'hls' ? line.hlsAntiCode : line.flvAntiCode,
    );
    const ext = line.lineType === 'hls' ? 'm3u8' : 'flv';
    let url = `${line.line}/${line.streamName}.${ext}?${antiCode}&codec=264`;
    if (bitRate > 0) {
      url += `&ratio=${bitRate}`;
    }
    return url;
  }

  async getLiveStatus(roomId: string): Promise<boolean> {
    const res = await upstream(`https://m.huya.com/${encodeURIComponent(roomId)}`, {
      headers: {
        'user-agent': K_HUYA_MOBILE_UA,
        accept: '*/*',
        origin: 'https://www.huya.com',
        referer: 'https://www.huya.com/',
      },
    });
    const match = /window\.HNF_GLOBAL_INIT.=.\{(.*?)\}.<\/script>/.exec(res.text);
    if (!match) return false;
    try {
      const jsonObj = JSON.parse(`{${match[1]}}`) as Record<string, any>;
      return jsonObj['roomInfo']?.['eLiveStatus'] === 2;
    } catch {
      return false;
    }
  }

  async sendDanmaku(_roomId: string, _message: string): Promise<[boolean, string]> {
    return [false, '虎牙暂不支持发送弹幕'];
  }
}

registerSite('huya', new HuyaSite());
export { buildAntiCode, getUid };
