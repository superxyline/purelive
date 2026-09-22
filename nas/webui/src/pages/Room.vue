<template>
  <div v-if="room" class="room-layout">
    <!-- 左：播放器（Twitch 观看页） -->
    <div class="room-player-col">
      <div class="room-player-wrap">
        <video ref="videoEl" autoplay playsinline style="width: 100%; height: 100%; object-fit: contain"></video>
        <n-spin v-if="playerLoading" style="position: absolute; inset: 0; display: flex; align-items: center; justify-content: center" size="large" />
        <div v-if="playError" class="room-play-error">
          播放失败：{{ playError }}
        </div>
      </div>
      <!-- 信息与控制条 -->
      <div class="room-meta">
        <div class="room-meta-row">
          <strong class="room-title-strong">{{ room.title }}</strong>
          <n-tag size="small" :bordered="false">{{ platformName }}</n-tag>
          <span class="room-nick">{{ room.nick }}</span>
          <span v-if="online" class="room-online">👁 {{ online }}</span>
          <div style="flex: 1"></div>
          <n-button size="small" @click="toggleFollowBtn">{{ followed ? '已关注' : '关注' }}</n-button>
          <n-button size="small" @click="toggleMute">{{ muted ? '取消静音' : '静音' }}</n-button>
          <n-select v-model:value="quality" size="small" style="width: 130px" :options="qualityOptions" @update:value="onQualityChange" />
          <n-select v-model:value="lineIndex" size="small" style="width: 110px" :options="lineOptions" @update:value="onLineChange" />
          <n-button size="small" @click="fullscreen">全屏</n-button>
        </div>
      </div>
    </div>

    <!-- 右：弹幕 / 礼物卡片 切换（Twitch chat 侧栏） -->
    <div class="room-chat">
      <div style="display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 10px 12px; border-bottom: 1px solid #2a2a2d">
        <div class="room-chat-header">
          <n-button-group size="tiny">
            <n-button :type="dmView === 'list' ? 'primary' : 'default'" @click="setDmView('list')">弹幕</n-button>
            <n-button :type="dmView === 'gift' ? 'primary' : 'default'" @click="setDmView('gift')">礼物</n-button>
          </n-button-group>
          <span style="font-size: 12px; color: #adadb8">
            {{ dmView === 'list' ? (danmaku.length ? danmaku.length + ' 条' : '') : (giftCards.length ? giftCards.length + ' 张' : '') }}
          </span>
        </div>
      </div>

      <!-- 模式一：现有弹幕列表 -->
      <div v-show="dmView === 'list'" ref="danmakuBox" class="room-chat-body">
        <div v-for="(d, i) in danmaku" :key="i" style="margin-bottom: 6px; word-break: break-all">
          <template v-if="d.type === 'msg'"><span class="room-chat-user">{{ d.userName }}</span><span style="color: #adadb8">: </span>{{ d.message }}</template>
          <template v-else-if="d.type === 'gift'"><span class="room-chat-gift">{{ d.userName }}</span> 送出 {{ d.giftName }} x{{ d.giftCount }}</template>
          <template v-else-if="d.type === 'sc'"><span class="room-chat-sc">【醒目留言】</span>{{ d.userName }}：{{ d.message }}</template>
        </div>
        <div v-if="!danmaku.length" class="room-chat-empty">暂无弹幕</div>
      </div>

      <!-- 模式二：安卓端礼物卡片 -->
      <div v-show="dmView === 'gift'" ref="giftBox" class="room-chat-body">
        <GiftCard
          v-for="g in giftCards"
          :key="g.id"
          :user-name="g.userName"
          :gift-name="g.giftName"
          :gift-count="g.giftCount"
          :gift-icon="g.giftIcon || ''"
          :platform="g.platform"
        />
        <div v-if="!giftCards.length" class="room-chat-empty">暂无礼物卡片</div>
      </div>

      <div class="room-chat-footer">
        <n-input v-model:value="dmInput" size="small" placeholder="发个弹幕（需登录）" @keyup.enter="send" :disabled="!canSend" />
        <n-button size="small" type="primary" :disabled="!canSend" @click="send">发送</n-button>
      </div>
    </div>
  </div>
  <n-spin v-else style="margin: 120px auto; display: block" />
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { api, withProxyFallback, toggleFollow, isFollowed } from '../api';
import GiftCard from '../components/GiftCard.vue';

const route = useRoute();
const router = useRouter();
const platform = route.params.platform;
const roomId = route.params.roomId;

const room = ref(null);
const videoEl = ref(null);
const danmakuBox = ref(null);
const giftBox = ref(null);
const danmaku = ref([]);
const giftCards = ref([]);
const online = ref('');
const playError = ref('');
const playerLoading = ref(true);
const quality = ref('');
const qualities = ref([]);
const urls = ref([]);
const lineIndex = ref(0);
const usingProxy = ref(false);
const muted = ref(false);
const dmInput = ref('');
const followed = ref(false);
const canSend = ['bilibili', 'douyu'].includes(platform);

// 弹幕区显示模式：list=文本弹幕 | gift=安卓礼物卡片（localStorage 记忆）
const DM_VIEW_KEY = 'purelive_room_dm_view';
const dmView = ref(localStorage.getItem(DM_VIEW_KEY) === 'gift' ? 'gift' : 'list');
function setDmView(v) {
  dmView.value = v;
  localStorage.setItem(DM_VIEW_KEY, v);
}

// 礼物合并窗口（对齐安卓 giftMergeWindow = 3s）：同用户同礼物在窗口内累加数量
const GIFT_MERGE_MS = 3000;
const giftMergeWindows = new Map();
let giftSeq = 0;

const platformName = { bilibili: '哔哩哔哩', douyu: '斗鱼', huya: '虎牙', douyin: '抖音', kuaishou: '快手' }[platform] || platform;

const qualityOptions = computed(() => qualities.value.map((q) => ({ label: q.quality, value: q.quality })));
const lineOptions = computed(() => urls.value.map((u, i) => ({ label: `线路${i + 1}`, value: i })));

// ---- 播放内核管理（mpegts/hls/原生 + 代理回退，参照 Flutter 版 WebVideoAdapter） ----
let handle = null;
let currentCandidates = [];
let candidateIdx = 0;
let videoAbort = null;

function destroyPlayer() {
  if (handle) { try { handle.destroy(); } catch (_) {} handle = null; }
  if (videoAbort) { videoAbort.abort(); videoAbort = null; }
  const v = videoEl.value;
  if (v) { v.removeAttribute('src'); try { v.load(); } catch (_) {} }
}

function signalError() { attachNext(); }

function attach(url) {
  const video = videoEl.value;
  if (!video) return;
  destroyPlayer();
  videoAbort = new AbortController();
  const onErr = () => signalError();
  video.addEventListener('error', onErr, { once: true, signal: videoAbort.signal });
  try {
    if (/\.m3u8(\?|$)/i.test(url) && window.Hls && window.Hls.isSupported()) {
      const hls = new window.Hls({ lowLatencyMode: true, backBufferLength: 30 });
      hls.on(window.Hls.Events.ERROR, (_, data) => { if (data && data.fatal) onErr(); });
      hls.loadSource(url);
      hls.attachMedia(video);
      handle = { destroy: () => { try { hls.destroy(); } catch (_) {} } };
    } else if (/\.flv(\?|$)/i.test(url) && window.mpegts && window.mpegts.getFeatureList().mseLivePlayback) {
      const p = window.mpegts.createPlayer({ type: 'flv', isLive: true, url }, { enableStashBuffer: false, liveBufferLatencyChasing: true });
      p.on(window.mpegts.Events.ERROR, () => onErr());
      p.attachMediaElement(video);
      p.load();
      handle = { destroy: () => { try { playerCleanup(p); } catch (_) {} } };
    } else {
      video.src = url;
      handle = { destroy: () => {} };
    }
  } catch (e) { onErr(); }
}

function playerCleanup(p) { try { p.pause(); p.unload(); p.detachMediaElement(); p.destroy(); } catch (_) {} }

/** 依候选列表依次尝试：直连 → 代理 → 下一线路 */
function attachNext() {
  if (candidateIdx >= currentCandidates.length) {
    playerLoading.value = false;
    playError.value = '所有线路均不可用';
    return;
  }
  const url = currentCandidates[candidateIdx++];
  console.log('[player] try', url.slice(0, 90));
  attach(url);
}

function startPlay() {
  playError.value = '';
  playerLoading.value = true;
  currentCandidates = urls.value.flatMap((u) => withProxyFallback(u));
  candidateIdx = 0;
  attachNext();
  // 5 秒后若仍在加载且内核无错误，视作正常起播（隐藏 loading 交给 video 事件）
  setTimeout(() => { playerLoading.value = false; }, 8000);
}

async function loadQualities() {
  const r = await api.playUrls(platform, roomId);
  qualities.value = r.qualities || [];
  if (!qualities.value.length) {
    playError.value = '房间未开播或读取清晰度失败';
    playerLoading.value = false;
    return;
  }
  quality.value = qualities.value[0].quality;
  await loadUrls();
}

async function loadUrls() {
  const r = await api.playUrls(platform, roomId, quality.value);
  urls.value = r.urls || [];
  if (!urls.value.length) { playError.value = '未获取到播放地址'; playerLoading.value = false; return; }
  lineIndex.value = 0;
  startPlay();
}

function onQualityChange(q) { quality.value = q; loadUrls(); }
function onLineChange(i) { lineIndex.value = i; currentCandidates = withProxyFallback(urls.value[i]); candidateIdx = 0; startPlay(); }

function toggleMute() { muted.value = !muted.value; if (videoEl.value) videoEl.value.muted = muted.value; }
function fullscreen() { videoEl.value?.parentElement?.requestFullscreen?.(); }
function toggleFollowBtn() {
  followed.value = toggleFollow({ platform, roomId, nick: room.value?.nick, title: room.value?.title, cover: room.value?.cover });
}

// ---- 礼物卡片：合并 + 入队（安卓 live_play_controller 的 3s 合并窗口） ----
function giftComboKey(m) {
  const user = m.userId || m.userName || '';
  return `${user}|${m.giftName || ''}`;
}

function pushGiftCard(m) {
  const count = Number(m.giftCount) > 0 ? Number(m.giftCount) : 1;
  const key = giftComboKey(m);
  const win = giftMergeWindows.get(key);
  if (win) {
    // 窗口内：累加到已显示卡片并刷新
    const card = giftCards.value.find((c) => c.id === win.id);
    if (card) {
      card.giftCount += count;
      clearTimeout(win.timer);
      win.timer = setTimeout(() => giftMergeWindows.delete(key), GIFT_MERGE_MS);
      return;
    }
  }
  const id = ++giftSeq;
  giftCards.value.push({
    id,
    userName: m.userName || '',
    userId: m.userId || '',
    giftName: m.giftName || m.message || '礼物',
    giftCount: count,
    giftIcon: m.giftIcon || '',
    platform,
  });
  if (giftCards.value.length > 80) giftCards.value.splice(0, giftCards.value.length - 80);
  const timer = setTimeout(() => giftMergeWindows.delete(key), GIFT_MERGE_MS);
  giftMergeWindows.set(key, { id, timer });
}

function scrollToBottom(boxRef) {
  nextTick(() => {
    const el = boxRef.value;
    if (el) el.scrollTop = el.scrollHeight;
  });
}

// 切到礼物页时滚到最新
watch(dmView, (v) => {
  if (v === 'gift') scrollToBottom(giftBox);
  else scrollToBottom(danmakuBox);
});

// ---- 弹幕 ----
let ws = null;
let dmRetry = null;
function connectDanmaku() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/api/danmaku/${platform}/${roomId}`);
  ws.onmessage = (ev) => {
    try {
      const m = JSON.parse(ev.data);
      if (m.type === 'online') { online.value = m.onlineCount ?? m.message; return; }
      danmaku.value.push(m);
      if (danmaku.value.length > 300) danmaku.value.splice(0, danmaku.value.length - 300);
      if (m.type === 'gift') {
        pushGiftCard(m);
        if (dmView.value === 'gift') scrollToBottom(giftBox);
      }
      if (dmView.value === 'list') scrollToBottom(danmakuBox);
    } catch (_) {}
  };
  ws.onclose = () => { dmRetry = setTimeout(connectDanmaku, 3000); };
}
async function send() {
  const text = dmInput.value.trim();
  if (!text) return;
  const r = await api.sendDanmaku(platform, roomId, text);
  window.$msg[r.ok ? 'success' : 'error'](r.message || (r.ok ? '已发送' : '发送失败'));
  if (r.ok) dmInput.value = '';
}

onMounted(async () => {
  followed.value = isFollowed(platform, roomId);
  try { room.value = await api.roomDetail(platform, roomId); } catch (e) { window.$msg.error('读取直播间信息失败: ' + e.message); }
  connectDanmaku();
  try { await loadQualities(); } catch (e) { playError.value = e.message; playerLoading.value = false; }
});
onUnmounted(() => {
  destroyPlayer();
  if (ws) { ws.onclose = null; ws.close(); }
  if (dmRetry) clearTimeout(dmRetry);
  for (const win of giftMergeWindows.values()) clearTimeout(win.timer);
  giftMergeWindows.clear();
});
</script>
