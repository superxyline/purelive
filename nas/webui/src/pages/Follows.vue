<template>
  <div>
    <n-card size="small" style="margin-bottom: 14px">
      <div style="display: flex; gap: 20px; align-items: center; flex-wrap: wrap">
        <div style="text-align: center">
          <canvas ref="syncCanvas" style="width: 120px; height: 120px; background: #fff; border-radius: 6px; padding: 5px; display: block"></canvas>
          <div style="font-size: 11px; color: #8b8b94; margin-top: 4px">App 扫码推送</div>
        </div>
        <div style="flex: 1; min-width: 260px; font-size: 13px; line-height: 1.9">
          <div><b>手机关注列表同步到 Web</b></div>
          <div style="color: #8b8b94">
            手机打开 App → 设置 → 备份与恢复 → 跨端传输（扫码推送），扫描左侧二维码，
            App 会把关注列表推送到 NAS。推送完成后点右侧按钮导入到本页。
          </div>
        </div>
        <div style="text-align: center">
          <n-button type="primary" @click="pullSynced" :loading="pulling" :disabled="syncedCount === 0">
            导入{{ syncedCount > 0 ? `(${syncedCount}个)` : '' }}
          </n-button>
          <div style="font-size: 11px; color: #8b8b94; margin-top: 4px">
            {{ syncedCount > 0 ? `NAS 已收到 ${syncedCount} 个` : 'NAS 尚未收到推送' }}
          </div>
        </div>
      </div>
    </n-card>
    <div style="display: flex; gap: 14px; margin-bottom: 14px; flex-wrap: wrap; align-items: center">
      <n-tabs type="segment" v-model:value="statusTab" style="min-width: 360px">
        <n-tab name="live">已开播</n-tab>
        <n-tab name="offline">未开播</n-tab>
        <n-tab name="all">已关注</n-tab>
      </n-tabs>
      <n-select v-model:value="platformFilter" size="small" :options="platformOptions" style="width: 140px" placeholder="全部平台" clearable />
      <n-button quaternary size="small" @click="refresh" :loading="loading">刷新状态</n-button>
    </div>

    <n-empty v-if="!loading && filtered.length === 0" :description="emptyText" style="margin: 80px 0" />
    <div v-else class="room-grid">
      <div v-for="r in filtered" :key="r.platform + r.roomId" class="room-card" @click="goRoom(r)">
        <div style="position: relative">
          <img class="room-cover" :src="r.cover" referrerpolicy="no-referrer" loading="lazy" />
          <span class="room-status" :style="r.liveStatus === 0 ? 'background:#18a058' : 'background:#666'">
            {{ r.liveStatus === 0 ? '直播中' : '未开播' }}
          </span>
          <span v-if="r.liveStatus === 0 && liveDuration(r)" class="room-duration">⏱ {{ liveDuration(r) }}</span>
          <span class="room-plat">{{ platformName(r.platform) }}</span>
        </div>
        <div class="room-title">{{ r.title || r.nick }}</div>
        <div class="room-sub"><span>{{ r.nick }}</span><span v-if="r.liveStatus === 0">🔥 {{ r.watching || r.popularity }}</span></div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import QRCode from 'qrcode';
import { api, getFollows, setFollows, PLATFORMS } from '../api';

const router = useRouter();
const rooms = ref([]);
const loading = ref(false);
const statusTab = ref('live');
const platformFilter = ref(null);

const platformOptions = PLATFORMS.map((p) => ({ label: p.name, value: p.id }));
const platformName = (id) => PLATFORMS.find((p) => p.id === id)?.name || id;

const emptyText = computed(() =>
  statusTab.value === 'live' ? '暂无已开播的关注直播间' : statusTab.value === 'offline' ? '暂无未开播的关注直播间' : '还没有关注任何直播间，去热门页点击卡片下方的关注按钮'
);

const filtered = computed(() => {
  let list = rooms.value;
  if (statusTab.value === 'live') list = list.filter((r) => r.liveStatus === 0);
  else if (statusTab.value === 'offline') list = list.filter((r) => r.liveStatus !== 0);
  if (platformFilter.value) list = list.filter((r) => r.platform === platformFilter.value);
  // 已开播的排前面，其余按热度
  return [...list].sort((a, b) => (b.liveStatus === 0) - (a.liveStatus === 0));
});

/** 开播时长（Flutter 版特色：关注列表显示已开播时长） */
function liveDuration(r) {
  if (!r.liveStartTime || r.liveStartTime <= 0) return '';
  const ms = Date.now() - r.liveStartTime;
  if (ms <= 0) return '';
  const mins = Math.floor(ms / 60000);
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return h > 0 ? `${h}小时${m}分` : `${m}分钟`;
}

function goRoom(r) { router.push(`/room/${r.platform}/${r.roomId}`); }

async function refresh() {
  const follows = getFollows();
  if (!follows.length) { rooms.value = []; return; }
  loading.value = true;
  const results = [];
  let idx = 0;
  async function worker() {
    while (idx < follows.length) {
      const f = follows[idx++];
      try {
        const d = await api.roomDetail(f.platform, f.roomId);
        results.push({ ...d, nick: d.nick || f.nick, cover: d.cover || f.cover, title: d.title || f.title });
      } catch (_) {
        results.push({ platform: f.platform, roomId: f.roomId, nick: f.nick, title: f.title, cover: f.cover, liveStatus: 3, watching: '', popularity: '' });
      }
    }
  }
  await Promise.all([worker(), worker(), worker(), worker()]);
  rooms.value = results;
  loading.value = false;
}

// ---- 手机 App 扫码同步 ----
const syncCanvas = ref(null);
const syncedCount = ref(0);
const pulling = ref(false);
let statusTimer = null;

async function pollSyncStatus() {
  try {
    const st = await fetch('/api/sync/status').then((r) => r.json());
    syncedCount.value = st.count || 0;
  } catch (_) {}
}

async function pullSynced() {
  pulling.value = true;
  try {
    const r = await fetch('/api/sync/follows').then((x) => x.json());
    const remote = r.list || [];
    if (!remote.length) { window.$msg.warning('NAS 上还没有收到手机推送'); return; }
    // 合并：本地已有 + 同步新增（按 platform:roomId 去重，同步来的覆盖本地同条目）
    const local = getFollows();
    const map = new Map(local.map((f) => [f.platform + ':' + f.roomId, f]));
    for (const f of remote) map.set(f.platform + ':' + f.roomId, f);
    localStorage.setItem('purelive_follows', JSON.stringify([...map.values()]));
    window.$msg.success(`已导入 ${remote.length} 个关注直播间`);
    await refresh();
  } catch (e) {
    window.$msg.error('导入失败: ' + e.message);
  }
  pulling.value = false;
}

onMounted(() => {
  refresh();
  // 二维码内容固定用 http 入口：手机 App 的原生 HTTP 客户端不信任自签证书，
  // 若页面在 https 下，扫到的 https 地址会让 App 端 TLS 握手直接失败（同步失败）。
  const syncTarget = `http://${location.hostname}:8090`;
  QRCode.toCanvas(syncCanvas.value, syncTarget, { width: 110, margin: 0 });
  pollSyncStatus();
  statusTimer = setInterval(pollSyncStatus, 5000);
});
onUnmounted(() => { if (statusTimer) clearInterval(statusTimer); });
</script>
