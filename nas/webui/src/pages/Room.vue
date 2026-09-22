<template>
  <div v-if="room" style="display: flex; gap: 14px; height: calc(100vh - 100px)">
    <!-- 左：播放器 -->
    <div style="flex: 1; display: flex; flex-direction: column; min-width: 0">
      <div style="position: relative; flex: 1; background: #000; border-radius: 8px; overflow: hidden">
        <video ref="videoEl" autoplay playsinline style="width: 100%; height: 100%; object-fit: contain"></video>
        <n-spin v-if="playerLoading" style="position: absolute; inset: 0; display: flex; align-items: center; justify-content: center" size="large" />
        <div v-if="playError" style="position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; color: #e88080">
          播放失败：{{ playError }}
        </div>
      </div>
      <!-- 信息与控制条 -->
      <div style="padding: 10px 4px">
        <div style="display: flex; align-items: center; gap: 12px; flex-wrap: wrap">
          <strong style="font-size: 15px">{{ room.title }}</strong>
          <n-tag size="small" :bordered="false">{{ platformName }}</n-tag>
          <span style="color: #8b8b94; font-size: 13px">{{ room.nick }}</span>
          <span v-if="online" style="color: #63e2b7; font-size: 13px">👁 {{ online }}</span>
          <div style="flex: 1"></div>
          <n-button size="small" @click="toggleFollowBtn">{{ followed ? '已关注' : '关注' }}</n-button>
          <n-button size="small" @click="toggleMute">{{ muted ? '取消静音' : '静音' }}</n-button>
          <n-select v-model:value="quality" size="small" style="width: 130px" :options="qualityOptions" @update:value="onQualityChange" />
          <n-select v-model:value="lineIndex" size="small" style="width: 110px" :options="lineOptions" @update:value="onLineChange" />
          <n-button size="small" @click="fullscreen">全屏</n-button>
        </div>
      </div>
    </div>

    <!-- 右：弹幕 -->
    <n-card
      size="small"
      style="width: 320px; display: flex; flex-direction: column"
      content-style="flex: 1; min-height: 0; display: flex; flex-direction: column; overflow: hidden"
      :bordered="true"
    >
      <template #header>弹幕 <span style="font-size: 12px; color: #8b8b94">{{ danmaku.length ? danmaku.length + ' 条' : '' }}</span></template>
      <div ref="danmakuBox" style="flex: 1; min-height: 0; overflow-y: auto; font-size: 13px; line-height: 1.7">
        <div v-for="(d, i) in danmaku" :key="i" style="margin-bottom: 4px; word-break: break-all">
          <template v-if="d.type === 'msg'"><span style="color: #63e2b7">{{ d.userName }}</span>：{{ d.message }}</template>
          <template v-else-if="d.type === 'gift'"><span style="color: #f2c97d">{{ d.userName }}</span> 送出 {{ d.giftName }} x{{ d.giftCount }}</template>
          <template v-else-if="d.type === 'sc'"><span style="color: #e88080">【醒目留言】</span>{{ d.userName }}：{{ d.message }}</template>
        </div>
      </div>
      <div style="display: flex; gap: 8px; margin-top: 8px; flex-shrink: 0">
        <n-input v-model:value="dmInput" size="small" placeholder="发个弹幕（需登录）" @keyup.enter="send" :disabled="!canSend" />
        <n-button size="small" type="primary" :disabled="!canSend" @click="send">发送</n-button>
      </div>
    </n-card>
  </div>
  <n-spin v-else style="margin: 120px auto; display: block" />
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { api, withProxyFallback, toggleFollow, isFollowed } from '../api';

const route = useRoute();
const router = useRouter();
const platform = route.params.platform;
const roomId = route.params.roomId;

const room = ref(null);
const videoEl = ref(null);
const danmakuBox = ref(null);
const danmaku = ref([]);
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
      nextTick(() => { if (danmakuBox.value) danmakuBox.value.scrollTop = danmakuBox.value.scrollHeight; });
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
});
</script>
