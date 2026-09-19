<template>
  <div>
    <n-tabs type="segment" v-model:value="platform" style="max-width: 560px; margin-bottom: 14px">
      <n-tab v-for="p in platforms" :key="p.id" :name="p.id">{{ p.name }}</n-tab>
    </n-tabs>
    <n-spin :show="loading">
      <n-empty v-if="!loading && rooms.length === 0" description="暂无直播间" style="margin: 80px 0" />
      <div v-else class="room-grid">
        <div v-for="r in rooms" :key="r.roomId" class="room-card" @click="goRoom(r)">
          <img class="room-cover" :src="r.cover" loading="lazy" @error="$event.target.style.opacity = 0" />
          <div class="room-title">{{ r.title }}</div>
          <div class="room-sub"><span>{{ r.nick }}</span><span>🔥 {{ r.watching || r.popularity }}</span></div>
        </div>
      </div>
    </n-spin>
    <div style="text-align: center; margin: 20px 0">
      <n-button :loading="loading" @click="loadMore" v-if="rooms.length > 0">加载更多</n-button>
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { api, PLATFORMS } from '../api';

const router = useRouter();
const platform = ref('bilibili');
const rooms = ref([]);
const loading = ref(false);
const page = ref(1);

async function load(reset) {
  if (reset) { page.value = 1; rooms.value = []; }
  loading.value = true;
  try { rooms.value.push(...(await api.recommend(platform.value, page.value))); }
  catch (e) { window.$msg?.error(String(e.message || e)); }
  loading.value = false;
}
function loadMore() { page.value += 1; load(false); }
function goRoom(r) { router.push(`/room/${r.platform}/${r.roomId}`); }

watch(platform, () => load(true), { immediate: true });
</script>
