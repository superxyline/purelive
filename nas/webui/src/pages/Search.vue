<template>
  <div>
    <div style="display: flex; gap: 12px; margin-bottom: 14px; max-width: 560px">
      <n-select v-model:value="platform" :options="platformOptions" style="width: 160px" />
      <n-input v-model:value="keyword" placeholder="搜索直播间 / 主播，回车搜索" @keyup.enter="doSearch" />
      <n-button type="primary" :loading="loading" @click="doSearch">搜索</n-button>
    </div>
    <n-empty v-if="!loading && searched && rooms.length === 0" description="没有找到相关直播间" style="margin: 60px 0" />
    <div v-else class="room-grid">
      <div v-for="r in rooms" :key="r.roomId" class="room-card" @click="$router.push(`/room/${r.platform}/${r.roomId}`)">
        <img class="room-cover" :src="r.cover" loading="lazy" @error="$event.target.style.opacity = 0" />
        <div class="room-title">{{ r.title }}</div>
        <div class="room-sub"><span>{{ r.nick }}</span><span>🔥 {{ r.watching || r.popularity }}</span></div>
      </div>
    </div>
    <div style="text-align: center; margin: 20px 0" v-if="rooms.length > 0">
      <n-button :loading="loading" @click="loadMore">加载更多</n-button>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { api, PLATFORMS } from '../api';

const platform = ref('bilibili');
const keyword = ref('');
const rooms = ref([]);
const loading = ref(false);
const searched = ref(false);
const page = ref(1);

const platformOptions = PLATFORMS.map((p) => ({ label: p.name, value: p.id }));

async function doSearch() {
  if (!keyword.value.trim()) return;
  page.value = 1;
  rooms.value = [];
  searched.value = true;
  await load();
}
async function load() {
  loading.value = true;
  try { rooms.value.push(...(await api.search(platform.value, keyword.value, page.value))); }
  catch (e) { window.$msg.error(String(e.message || e)); }
  loading.value = false;
}
function loadMore() { page.value += 1; load(); }
</script>
