<template>
  <div>
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
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { api, getFollows, PLATFORMS } from '../api';

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

onMounted(refresh);
</script>
