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

        <!-- 浮层开关（右上，localStorage 记忆） -->
        <div class="fs-toggles">
          <n-button size="tiny" :type="overlayDm ? 'primary' : 'secondary'" @click="toggleOverlayDm">弹幕</n-button>
          <n-button size="tiny" :type="overlayGift ? 'primary' : 'secondary'" @click="toggleOverlayGift">礼物卡片</n-button>
        </div>

        <!-- 飘屏弹幕（仅普通弹幕进入，礼物/醒目留言不飘） -->
        <div v-if="overlayDm && floatDms.length" class="fs-danmaku">
          <span
            v-for="d in floatDms"
            :key="d.id"
            class="fs-dm-item"
            :style="{ top: d.lane * 30 + 10 + 'px', animationDuration: d.flyMs + 'ms' }"
          >
            {{ d.message }}
          </span>
        </div>

        <!-- 左下角礼物卡片（安卓 showFullscreenGift：价格分档时长 + 堆叠） -->
        <div v-if="overlayGift && fsGifts.length" class="fs-gift-stack">
          <GiftCard
            v-for="g in fsGifts"
            :key="g.id"
            :user-name="g.userName"
            :gift-name="g.giftName"
            :gift-count="g.giftCount"
            :gift-icon="g.giftIcon || ''"
            :platform="g.platform"
          />
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
          <n-slider v-model:value="volume" size="small" style="width: 86px" :min="0" :max="1" :step="0.05" @update:value="onVolumeChange" />
          <n-button size="small" @click="toggleMute">{{ muted ? '取消静音' : '静音' }}</n-button>
          <n-select v-model:value="quality" size="small" style="width: 130px" :options="qualityOptions" @update:value="onQualityChange" />
          <span
            v-if="hevcAvailable"
            class="hevc-toggle"
            :class="{ 'is-on': preferHevc }"
            title="H.265 编码：省流量，需浏览器支持硬解"
            @click="toggleHevc"
          >HEVC</span>
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
        <n-button size="tiny" quaternary @click="showShield = true">屏蔽</n-button>
      </div>

      <!-- 模式一：弹幕列表（回看：非底部不强滚，10s 无操作自动回底；右键条目屏蔽该用户） -->
      <div v-show="dmView === 'list'" ref="danmakuBox" class="room-chat-body" @scroll="onDmScroll">
        <div
          v-for="(d, i) in danmaku"
          :key="i"
          class="dm-row"
          @contextmenu.prevent="shieldUserOf(d)"
        >
          <template v-if="d.type === 'msg'"><span class="room-chat-user">{{ d.userName }}</span><span style="color: #adadb8">: </span>{{ d.message }}</template>
          <template v-else-if="d.type === 'sc'"><span class="room-chat-sc">【醒目留言】</span>{{ d.userName }}：{{ d.message }}</template>
        </div>
        <div v-if="!danmaku.length" class="room-chat-empty">暂无弹幕</div>
      </div>
      <button v-if="dmView === 'list' && dmUnread > 0" class="dm-back-bottom" @click="jumpDmBottom">
        ↓ {{ dmUnread }} 条新弹幕
      </button>

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

      <!-- 仅 B站可真实发送弹幕；其余平台后端不支持，直接不显示发送框 -->
      <div v-if="canSend" class="room-chat-footer">
        <n-input v-model:value="dmInput" size="small" placeholder="发个弹幕（需登录）" @keyup.enter="send" :disabled="!canSend" />
        <n-button size="small" type="primary" :disabled="!canSend" @click="send">发送</n-button>
      </div>
    </div>
  </div>
  <n-spin v-else style="margin: 120px auto; display: block" />

  <!-- 弹幕屏蔽管理：普通词包含即屏蔽 / /正则/ / 通配 *?；用户名包含即屏蔽 -->
  <n-modal v-model:show="showShield" preset="card" title="弹幕屏蔽" style="width: 460px">
    <div class="shield-sec">屏蔽词（普通词 / 正则 /xxx/ / 通配符 * ?）</div>
    <n-dynamic-tags v-model:value="shield.words" />
    <div class="shield-sec" style="margin-top: 16px">屏蔽用户（用户名包含即屏蔽）</div>
    <n-dynamic-tags v-model:value="shield.users" />
    <div class="shield-sec" style="margin-top: 16px">重复与相似过滤</div>
    <div style="display: flex; gap: 20px">
      <n-switch v-model:value="shield.collapse" size="small" />
      <span class="shield-hint" style="margin: 0">5 秒内相同文案只显示首条</span>
    </div>
    <div style="display: flex; gap: 20px; margin-top: 8px; align-items: center">
      <n-switch v-model:value="shield.similar" size="small" />
      <span class="shield-hint" style="margin: 0">过滤高度相似的刷屏弹幕（8 秒窗口）</span>
    </div>
    <div class="shield-hint">修改即时生效，存在本浏览器；右键弹幕可快捷屏蔽该用户。</div>
  </n-modal>
</template>

<script setup>
import { ref, reactive, computed, onMounted, onUnmounted, nextTick, watch } from 'vue';
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
const canSend = platform === 'bilibili';

// ---- 清晰度 / 音量 / 静音记忆（localStorage；音量额外按房间记忆） ----
const QUALITY_KEY = 'purelive_pref_quality';
const VOL_KEY = 'purelive_pref_volume';
const MUTE_KEY = 'purelive_pref_muted';
const ROOM_VOL_KEY = `purelive_room_vol_${platform}_${roomId}`;
const volume = ref(1);

function applyVolume() {
  const v = videoEl.value;
  if (v) {
    v.volume = Math.min(1, Math.max(0, volume.value));
    v.muted = muted.value;
  }
}
function onVolumeChange(val) {
  volume.value = val;
  localStorage.setItem(VOL_KEY, String(val));
  localStorage.setItem(ROOM_VOL_KEY, String(val));
  if (muted.value) {
    muted.value = false;
    localStorage.setItem(MUTE_KEY, '0');
  }
  applyVolume();
}
function toggleMute() {
  muted.value = !muted.value;
  localStorage.setItem(MUTE_KEY, muted.value ? '1' : '0');
  applyVolume();
}

// ---- HEVC 开关（仅 B站；浏览器不支持 hvc1 硬解时不显示） ----
const HEVC_KEY = 'purelive_pref_hevc';
const hevcAvailable = computed(() => {
  if (platform !== 'bilibili') return false;
  return document.createElement('video').canPlayType('video/mp4; codecs="hvc1.1.6.L93.B0"') !== '';
});
const preferHevc = ref(localStorage.getItem(HEVC_KEY) === '1');
function toggleHevc() {
  preferHevc.value = !preferHevc.value;
  localStorage.setItem(HEVC_KEY, preferHevc.value ? '1' : '0');
  loadUrls();
}

// ---- 起播 watchdog：7 秒内没出任何视频帧自动换下一候选（对齐安卓 player_manager） ----
const rvfcSupported = typeof HTMLVideoElement !== 'undefined' && 'requestVideoFrameCallback' in HTMLVideoElement.prototype;
let frameWatchdog = null;
let playGen = 0;
let frameSeen = false;

// ---- 弹幕回看：非底部不强推 + 未读计数 + 10s 无操作自动回底（对齐安卓 danmaku_list_view） ----
const dmUnread = ref(0);
const dmAtBottom = ref(true);
let dmResumeTimer = null;

function onDmScroll() {
  const el = danmakuBox.value;
  if (!el) return;
  if (el.scrollHeight - el.scrollTop - el.clientHeight < 60) {
    dmAtBottom.value = true;
    if (dmUnread.value) dmUnread.value = 0;
    if (dmResumeTimer) { clearTimeout(dmResumeTimer); dmResumeTimer = null; }
  } else {
    dmAtBottom.value = false;
    if (dmResumeTimer) clearTimeout(dmResumeTimer);
    dmResumeTimer = setTimeout(jumpDmBottom, 10000);
  }
}
function jumpDmBottom() {
  if (dmResumeTimer) { clearTimeout(dmResumeTimer); dmResumeTimer = null; }
  dmAtBottom.value = true;
  dmUnread.value = 0;
  scrollToBottom(danmakuBox);
}

// ---- 弹幕屏蔽：关键词 / 正则 / 通配 + 用户名（localStorage 持久，改动即时生效） ----
const SHIELD_KEY = 'purelive_shield';
const showShield = ref(false);
const shield = reactive(loadShield());
let shieldRegexes = [];
let shieldKw = [];
let shieldWild = [];
let shieldUserFrags = [];

function loadShield() {
  try {
    const s = JSON.parse(localStorage.getItem(SHIELD_KEY));
    return {
      words: Array.isArray(s?.words) ? s.words : [],
      users: Array.isArray(s?.users) ? s.users : [],
      // 上游移植（Web 版）：短窗口重复合并 + 相似过滤，默认关
      collapse: s?.collapse === true,
      similar: s?.similar === true,
    };
  } catch (_) {
    return { words: [], users: [], collapse: false, similar: false };
  }
}
function wildToRegExp(pat) {
  const esc = pat.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/\?/g, '.');
  return new RegExp(`^${esc}$`, 'i');
}
function rebuildShield() {
  shieldRegexes = [];
  shieldKw = [];
  shieldWild = [];
  shieldUserFrags = shield.users.map((u) => String(u).toLowerCase()).filter(Boolean);
  for (const w of shield.words) {
    const m = /^\/(.+)\/([imsu]*)$/.exec(w);
    if (m) {
      try { shieldRegexes.push(new RegExp(m[1], m[2] || 'i')); } catch (_) {}
    } else if (w.includes('*') || w.includes('?')) {
      try { shieldWild.push(wildToRegExp(w)); } catch (_) {}
    } else if (w) {
      shieldKw.push(w.toLowerCase());
    }
  }
}
function isShielded(m) {
  const user = String(m.userName || '').toLowerCase();
  if (shieldUserFrags.some((u) => user.includes(u))) return true;
  const text = String(m.message || '');
  const lower = text.toLowerCase();
  if (shieldKw.some((k) => lower.includes(k))) return true;
  if (shieldRegexes.some((r) => r.test(text))) return true;
  if (shieldWild.some((r) => r.test(text))) return true;
  return false;
}
function shieldUserOf(d) {
  const u = String(d.userName || '').trim();
  if (!u) return;
  if (!shield.users.includes(u)) {
    shield.users.push(u);
    window.$msg.success(`已屏蔽用户「${u}」`);
  }
}

// ---- 重复合并 + 相似过滤（对齐安卓 RepeatedDanmakuFilter / DanmakuSimilarityFilter 简化版） ----
const REPEAT_WINDOW_MS = 5000;
const repeatedSeen = new Map(); // 归一化文本 → 上次时间
const similarCache = []; // { text, bigrams:Set, at }

function normalizeDmText(t) {
  return String(t || '').trim().replace(/\s+/g, ' ').toLowerCase();
}
function acceptRepeated(m) {
  if (!shield.collapse) return true;
  const now = Date.now();
  const key = normalizeDmText(m.message);
  if (!key) return true;
  const prev = repeatedSeen.get(key);
  repeatedSeen.set(key, now);
  // 有界清理
  if (repeatedSeen.size > 512) {
    for (const [k, t] of repeatedSeen) {
      if (now - t > REPEAT_WINDOW_MS) repeatedSeen.delete(k);
      if (repeatedSeen.size <= 512) break;
    }
  }
  return prev == null || now - prev > REPEAT_WINDOW_MS;
}
function bigramsOf(text) {
  const s = normalizeDmText(text).replace(/\s/g, '');
  const set = new Set();
  for (let i = 0; i < s.length - 1; i++) set.add(s.slice(i, i + 2));
  if (s.length === 1) set.add(s);
  return set;
}
function jaccard(a, b) {
  if (!a.size || !b.size) return 0;
  let inter = 0;
  for (const g of a) if (b.has(g)) inter++;
  return inter / (a.size + b.size - inter);
}
function acceptSimilar(m) {
  if (!shield.similar) return true;
  const text = normalizeDmText(m.message);
  if (!text) return true;
  const now = Date.now();
  const grams = bigramsOf(text);
  for (let i = similarCache.length - 1; i >= 0; i--) {
    const c = similarCache[i];
    if (now - c.at > 8000) {
      similarCache.splice(i, 1);
      continue;
    }
    if (jaccard(grams, c.bigrams) >= 0.85) return false;
  }
  similarCache.push({ text, bigrams: grams, at: now });
  if (similarCache.length > 100) similarCache.shift();
  return true;
}
watch(shield, () => {
  localStorage.setItem(SHIELD_KEY, JSON.stringify(shield));
  rebuildShield();
}, { deep: true });
rebuildShield();

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

// ---- 播放器浮层开关（右上按钮，localStorage 记忆，默认开） ----
const OVERLAY_DM_KEY = 'purelive_room_overlay_dm';
const OVERLAY_GIFT_KEY = 'purelive_room_overlay_gift';
const overlayDm = ref(localStorage.getItem(OVERLAY_DM_KEY) !== '0');
const overlayGift = ref(localStorage.getItem(OVERLAY_GIFT_KEY) !== '0');
function toggleOverlayDm() {
  overlayDm.value = !overlayDm.value;
  localStorage.setItem(OVERLAY_DM_KEY, overlayDm.value ? '1' : '0');
  if (!overlayDm.value) {
    for (const d of floatDms.value) clearTimeout(d.timer);
    floatDms.value = [];
  }
}
function toggleOverlayGift() {
  overlayGift.value = !overlayGift.value;
  localStorage.setItem(OVERLAY_GIFT_KEY, overlayGift.value ? '1' : '0');
  if (!overlayGift.value) clearFsGifts();
}

// ---- 飘屏弹幕：普通弹幕从右向左飞过，礼物/SC 不进飘屏 ----
const FLOAT_DM_MAX = 40;
const floatDms = ref([]);
let floatSeq = 0;
let laneSeq = 0;
function pushFloatDm(m) {
  const flyMs = 9000;
  const d = {
    id: ++floatSeq,
    message: String(m.message || '').slice(0, 100),
    lane: laneSeq++ % 9,
    flyMs,
    timer: null,
  };
  d.timer = setTimeout(() => {
    const i = floatDms.value.findIndex((x) => x.id === d.id);
    if (i >= 0) floatDms.value.splice(i, 1);
  }, flyMs + 300);
  floatDms.value.push(d);
  if (floatDms.value.length > FLOAT_DM_MAX) {
    const old = floatDms.value.shift();
    if (old) clearTimeout(old.timer);
  }
}

// ---- 左下角礼物卡片（安卓 showFullscreenGift）：价格分档时长 + 3s 合并窗 + 最多 5 张堆叠 ----
const FS_GIFT_MAX = 5;
const fsGifts = ref([]);
const fsMergeWindows = new Map();
const fsHideTimers = new Map();
let fsSeq = 0;

/** 与安卓 _giftDurationTiers 对齐：(价格上限, 秒) */
function giftDurationMs(price) {
  const p = Number(price) > 0 ? Number(price) : 0;
  if (p <= 10) return 3000;
  if (p <= 100) return 5000;
  if (p <= 1000) return 8000;
  return 12000;
}

function startFsHideTimer(card) {
  clearTimeout(fsHideTimers.get(card.id));
  fsHideTimers.set(
    card.id,
    setTimeout(() => {
      fsHideTimers.delete(card.id);
      const i = fsGifts.value.findIndex((c) => c.id === card.id);
      if (i >= 0) fsGifts.value.splice(i, 1);
    }, giftDurationMs(card.giftPrice)),
  );
}

function pushFsGift(m) {
  const count = Number(m.giftCount) > 0 ? Number(m.giftCount) : 1;
  const key = giftComboKey(m);
  const win = fsMergeWindows.get(key);
  if (win) {
    // 合并窗内同用户同礼物：累加数量并重置显示计时（安卓 _mergeFullscreenGift）
    const card = fsGifts.value.find((c) => c.id === win.id);
    if (card) {
      card.giftCount += count;
      clearTimeout(win.timer);
      win.timer = setTimeout(() => fsMergeWindows.delete(key), GIFT_MERGE_MS);
      startFsHideTimer(card);
      return;
    }
  }
  while (fsGifts.value.length >= FS_GIFT_MAX) {
    const old = fsGifts.value.shift();
    clearTimeout(fsHideTimers.get(old.id));
    fsHideTimers.delete(old.id);
  }
  const card = {
    id: ++fsSeq,
    userName: m.userName || '',
    giftName: m.giftName || m.message || '礼物',
    giftCount: count,
    giftIcon: m.giftIcon || '',
    platform,
    giftPrice: m.giftPrice || 0,
  };
  fsGifts.value.push(card);
  startFsHideTimer(card);
  const timer = setTimeout(() => fsMergeWindows.delete(key), GIFT_MERGE_MS);
  fsMergeWindows.set(key, { id: card.id, timer });
}

function clearFsGifts() {
  for (const t of fsHideTimers.values()) clearTimeout(t);
  fsHideTimers.clear();
  for (const w of fsMergeWindows.values()) clearTimeout(w.timer);
  fsMergeWindows.clear();
  fsGifts.value = [];
}

const platformName = { bilibili: '哔哩哔哩', douyu: '斗鱼', huya: '虎牙', douyin: '抖音', kuaishou: '快手' }[platform] || platform;

const qualityOptions = computed(() => qualities.value.map((q) => ({ label: q.quality, value: q.quality })));
const lineOptions = computed(() => urls.value.map((u, i) => ({ label: `线路${i + 1}`, value: i })));

// ---- 播放内核管理（mpegts/hls/原生 + 代理回退，参照 Flutter 版 WebVideoAdapter） ----
let handle = null;
let currentCandidates = [];
let candidateIdx = 0;
let videoAbort = null;

function destroyPlayer() {
  playGen++; // 使旧的帧回调 / watchdog 全部失效
  if (frameWatchdog) { clearTimeout(frameWatchdog); frameWatchdog = null; }
  if (handle) { try { handle.destroy(); } catch (_) {} handle = null; }
  if (videoAbort) { videoAbort.abort(); videoAbort = null; }
  const v = videoEl.value;
  if (v) { v.removeAttribute('src'); try { v.load(); } catch (_) {} }
}

function signalError() { attachNext(); }

function attach(url) {
  const video = videoEl.value;
  if (!video) return;
  destroyPlayer(); // 内部 playGen++
  const gen = playGen;
  frameSeen = false;
  videoAbort = new AbortController();
  const onErr = () => signalError();
  video.addEventListener('error', onErr, { once: true, signal: videoAbort.signal });
  if (rvfcSupported) {
    // 首帧到达即视为起播成功：关 loading、撤 watchdog
    video.requestVideoFrameCallback(() => {
      if (gen !== playGen || frameSeen) return;
      frameSeen = true;
      playerLoading.value = false;
      if (frameWatchdog) { clearTimeout(frameWatchdog); frameWatchdog = null; }
    });
    // 7 秒仍无帧：换下一候选（直连→代理→下一线路）
    frameWatchdog = setTimeout(() => {
      if (gen === playGen && !frameSeen) {
        console.log('[player] no frame in 7s, fallback');
        attachNext();
      }
    }, 7000);
  }
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
  // 首选清晰度记忆：上次选过的还在就用它
  const savedQ = localStorage.getItem(QUALITY_KEY);
  quality.value = savedQ && qualities.value.some((q) => q.quality === savedQ) ? savedQ : qualities.value[0].quality;
  await loadUrls();
}

function hostOf(u) {
  try { return new URL(u, location.href).hostname; } catch (_) { return ''; }
}

/** B站多 CDN：TCP 握手测速后按延迟升序（对齐安卓 CdnSpeedTest），失败静默保持原序。 */
async function sortUrlsBySpeed() {
  try {
    const hosts = [...new Set(urls.value.map(hostOf).filter(Boolean))];
    if (hosts.length < 2) return;
    const lat = await api.speedTest(hosts);
    urls.value = [...urls.value].sort((a, b) => (lat[hostOf(a)] ?? 9999) - (lat[hostOf(b)] ?? 9999));
  } catch (_) {}
}

async function loadUrls() {
  const codec = platform === 'bilibili' && preferHevc.value ? 'hevc' : undefined;
  const r = await api.playUrls(platform, roomId, quality.value, codec);
  urls.value = r.urls || [];
  if (!urls.value.length) { playError.value = '未获取到播放地址'; playerLoading.value = false; return; }
  if (platform === 'bilibili' && urls.value.length > 1) await sortUrlsBySpeed();
  lineIndex.value = 0;
  startPlay();
}

function onQualityChange(q) {
  quality.value = q;
  localStorage.setItem(QUALITY_KEY, q);
  loadUrls();
}
function onLineChange(i) { lineIndex.value = i; currentCandidates = withProxyFallback(urls.value[i]); candidateIdx = 0; startPlay(); }

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

// 切页签：礼物页滚到最新；弹幕页回底并清未读
watch(dmView, (v) => {
  if (v === 'gift') scrollToBottom(giftBox);
  else jumpDmBottom();
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
      if (m.type === 'gift') {
        // 礼物不进弹幕列表：只走右侧礼物页签与左下角浮层
        pushGiftCard(m);
        if (overlayGift.value) pushFsGift(m);
        if (dmView.value === 'gift') scrollToBottom(giftBox);
        return;
      }
      if ((m.type === 'msg' || m.type === 'sc') && isShielded(m)) return;
      if (m.type === 'msg') {
        if (!acceptRepeated(m)) return;
        if (!acceptSimilar(m)) return;
      }
      danmaku.value.push(m);
      if (danmaku.value.length > 300) danmaku.value.splice(0, danmaku.value.length - 300);
      if (m.type === 'msg' && overlayDm.value) pushFloatDm(m);
      if (dmView.value === 'list') {
        // 回看中（不在底部）不打断：累计未读，底部才自动滚
        if (dmAtBottom.value) scrollToBottom(danmakuBox);
        else dmUnread.value++;
      }
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
  // 音量/静音：每房间音量优先，其次全局；初始化后应用到 video 元素
  const roomVol = parseFloat(localStorage.getItem(ROOM_VOL_KEY) ?? '');
  const globalVol = parseFloat(localStorage.getItem(VOL_KEY) ?? '');
  volume.value = !Number.isNaN(roomVol) ? roomVol : !Number.isNaN(globalVol) ? globalVol : 1;
  muted.value = localStorage.getItem(MUTE_KEY) === '1';
  await nextTick();
  applyVolume();
  try { room.value = await api.roomDetail(platform, roomId); } catch (e) { window.$msg.error('读取直播间信息失败: ' + e.message); }
  connectDanmaku();
  try { await loadQualities(); } catch (e) { playError.value = e.message; playerLoading.value = false; }
});
onUnmounted(() => {
  destroyPlayer();
  if (ws) { ws.onclose = null; ws.close(); }
  if (dmRetry) clearTimeout(dmRetry);
  if (dmResumeTimer) clearTimeout(dmResumeTimer);
  for (const win of giftMergeWindows.values()) clearTimeout(win.timer);
  giftMergeWindows.clear();
  for (const d of floatDms.value) clearTimeout(d.timer);
  floatDms.value = [];
  clearFsGifts();
});
</script>
