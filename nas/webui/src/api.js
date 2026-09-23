/** 后端 REST 客户端：全部走同源 /api（nginx 反代到 Node 后端）。 */

export const PLATFORMS = [
  { id: 'bilibili', name: '哔哩哔哩' },
  { id: 'douyu', name: '斗鱼' },
  { id: 'huya', name: '虎牙' },
  { id: 'douyin', name: '抖音' },
  { id: 'kuaishou', name: '快手' },
];

async function get(url) {
  const res = await fetch(url);
  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try { msg = (await res.json()).error || msg; } catch (_) {}
    throw new Error(msg);
  }
  return res.json();
}

export const api = {
  categories: (p) => get(`/api/sites/${p}/categories?page=1&size=200`).then((d) => d.data || []),
  categoryRooms: (p, cateId, typeName, page = 1) =>
    get(`/api/sites/${p}/categories/${cateId}/rooms?page=${page}&size=24&typeName=${encodeURIComponent(typeName || '')}`).then((d) => d.data || []),
  recommend: (p, page = 1) => get(`/api/sites/${p}/recommend?page=${page}&size=24`).then((d) => d.data || []),
  search: (p, q, page = 1) => get(`/api/sites/${p}/search?q=${encodeURIComponent(q)}&page=${page}&size=24`).then((d) => d.data || []),
  searchAnchors: (p, q, page = 1) => get(`/api/sites/${p}/search?q=${encodeURIComponent(q)}&page=${page}&size=24&anchors=true`).then((d) => d.data || []),
  roomDetail: (p, roomId) => get(`/api/sites/${p}/rooms/${roomId}`).then((d) => d.data),
  liveStatus: (p, roomId) => get(`/api/sites/${p}/rooms/${roomId}/live-status`).then((d) => !!d.live),
  playUrls: (p, roomId, quality, codec) => {
    const params = new URLSearchParams();
    if (quality) params.set('quality', quality);
    if (codec) params.set('codec', codec);
    const qs = params.toString();
    return get(`/api/sites/${p}/rooms/${roomId}/play-urls${qs ? `?${qs}` : ''}`);
  },
  speedTest: (hosts) =>
    get(`/api/sites/speedtest?hosts=${encodeURIComponent(hosts.join(','))}`).then((d) => d.data || {}),
  sendDanmaku: (p, roomId, message) =>
    fetch(`/api/sites/${p}/danmaku/send`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ roomId, message }),
    }).then((r) => r.json()),
  authStatus: () => get('/api/auth/status').then((d) => d.platforms || {}),
  bilibiliQr: () => get('/api/auth/bilibili/qrcode').then((d) => d.data),
  bilibiliPoll: (key) => get(`/api/auth/bilibili/qrcode/poll?qrcode_key=${encodeURIComponent(key)}`),
  bilibiliSession: () => get('/api/auth/bilibili/session'),
  syncFollows: () => get('/api/sync/follows'),
  saveSyncFollows: (list) =>
    fetch('/api/sync/follows', {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ list }),
    }).then((r) => r.json()),
  saveCookie: (p, cookie) =>
    fetch(`/api/auth/${p}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ cookie }) }).then((r) => r.json()),
  clearAuth: (p) => fetch(`/api/auth/${p}`, { method: 'DELETE' }).then((r) => r.json()),
};

/** 直播流地址：直连失败时改走后端代理（参考 Flutter 版 WebVideoAdapter 的回退策略）。 */
export function withProxyFallback(url) {
  return [url, `/api/stream/proxy?url=${encodeURIComponent(url)}`];
}

/** 关注列表：localStorage 为操作源，变化后防抖写穿到 NAS（服务端持久化，换浏览器可恢复）。 */
const FOLLOW_KEY = 'purelive_follows';
let followPushTimer = null;
function pushFollowsSoon() {
  clearTimeout(followPushTimer);
  followPushTimer = setTimeout(() => {
    fetch('/api/sync/follows', {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ list: getFollows() }),
    }).catch(() => {});
  }, 800);
}
export function getFollows() {
  try { return JSON.parse(localStorage.getItem(FOLLOW_KEY)) || []; } catch (_) { return []; }
}
export function isFollowed(platform, roomId) {
  return getFollows().some((f) => f.platform === platform && f.roomId === roomId);
}
export function setFollows(list) {
  localStorage.setItem(FOLLOW_KEY, JSON.stringify(list.slice(0, 500)));
  pushFollowsSoon();
}
export function toggleFollow(room) {
  const list = getFollows();
  const idx = list.findIndex((f) => f.platform === room.platform && f.roomId === room.roomId);
  if (idx >= 0) list.splice(idx, 1);
  else list.unshift({ platform: room.platform, roomId: room.roomId, nick: room.nick, title: room.title, cover: room.cover });
  localStorage.setItem(FOLLOW_KEY, JSON.stringify(list.slice(0, 200)));
  pushFollowsSoon();
  return idx < 0;
}
/** 本地关注为空时从 NAS 恢复（换浏览器/清缓存后自动找回）。返回是否恢复了数据。 */
export async function restoreFollowsFromServer() {
  if (getFollows().length) return false;
  try {
    const r = await fetch('/api/sync/follows').then((x) => x.json());
    if (Array.isArray(r.list) && r.list.length) {
      localStorage.setItem(FOLLOW_KEY, JSON.stringify(r.list.slice(0, 500)));
      return true;
    }
  } catch (_) {}
  return false;
}
