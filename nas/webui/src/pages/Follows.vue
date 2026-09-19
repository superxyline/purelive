<template>
  <div>
    <n-empty v-if="!loading && rooms.length === 0" description="还没有关注的直播间，去热门页点击卡片右下角" style="margin: 80px 0">
      <template #extra>
        <n-button @click="$router.push('/')">去热门</n-button>
      </template>
    </n-empty>
    <n-spin :show="loading">
      <div class="room-grid">
        <div v-for="r in rooms" :key="r.platform + r.roomId" class="room-card" @click="$router.push(`/room/${r.platform}/${r.roomId}`)">
          <img class="room-cover" :src="r.cover" loading="lazy" @error="$event.target.style.opacity = 0" />
          <div class="room-title">{{ r.liveStatus === 0 ? '🔴 ' : '⚫ ' }}{{ r.title || r.nick }}</div>
          <div class="room-sub"><span>{{ r.nick }}</span><span v-if="r.liveStatus === 0">🔥 {{ r.watching || r.popularity }}</span></div>
        </div>
      </div>
    </n-spin>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { api, getFollows } from '../api';

const rooms = ref([]);
const loading = ref(false);

onMounted(async () => {
  const follows = getFollows();
  if (!follows.length) return;
  loading.value = true;
  // 并发查询每个关注房间的最新状态（后端逐个解析，限 4 路并发）
  const results = [];
  let idx = 0;
  async function worker() {
    while (idx < follows.length) {
      const f = follows[idx++];
      try {
        const d = await api.roomDetail(f.platform, f.roomId);
        results.push({ ...d, nick: d.nick || f.nick, cover: d.cover || f.cover, title: d.title || f.title });
      } catch (_) {
        results.push({ platform: f.platform, roomId: f.roomId, nick: f.nick, title: f.title, cover: f.cover, liveStatus: 3, watching: '' });
      }
    }
  }
  await Promise.all([worker(), worker(), worker(), worker()]);
  rooms.value = results;
  loading.value = false;
});
</script>
