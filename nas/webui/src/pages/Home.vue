<template>
  <div>
    <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 14px; flex-wrap: wrap">
      <n-button-group size="small">
        <n-button v-for="p in platformTabs" :key="p.id" :type="platform === p.id ? 'primary' : 'default'" @click="platform = p.id">
          {{ p.name }}
        </n-button>
      </n-button-group>
      <n-button size="small" quaternary @click="goArea">按分区浏览 →</n-button>
    </div>
    <n-spin :show="loading">
      <n-empty v-if="!loading && rooms.length === 0" description="暂无直播间" style="margin: 80px 0" />
      <div v-else class="room-grid">
        <div v-for="r in rooms" :key="r.platform + r.roomId" class="room-card" @click="goRoom(r)">
          <div style="position: relative">
            <img class="room-cover" :src="r.cover" referrerpolicy="no-referrer" loading="lazy" />
            <span class="room-plat">{{ platformName(r.platform) }}</span>
          </div>
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
const platformTabs = [{ id: 'all', name: '全部' }, ...PLATFORMS];
const platform = ref('all');
const rooms = ref([]);
const loading = ref(false);
const page = ref(1);

const platformName = (id) => PLATFORMS.find((p) => p.id === id)?.name || id;

async function load(reset) {
  if (reset) { page.value = 1; rooms.value = []; }
  loading.value = true;
  try {
    if (platform.value === 'all') {
      // 聚合模式：并发拉五平台推荐，交错合并
      const results = await Promise.allSettled(PLATFORMS.map((p) => api.recommend(p.id, page.value).catch(() => [])));
      const merged = [];
      const maxLen = Math.max(...results.map((r) => (r.value ? r.value.length : 0)), 0);
      for (let i = 0; i < maxLen; i++) {
        for (const r of results) {
          if (r.value && r.value[i]) merged.push(r.value[i]);
        }
      }
      if (reset) rooms.value = merged;
      else rooms.value.push(...merged);
    } else {
      rooms.value.push(...(await api.recommend(platform.value, page.value)));
    }
  } catch (e) { window.$msg?.error(String(e.message || e)); }
  loading.value = false;
}
function loadMore() { page.value += 1; load(false); }
function goRoom(r) { router.push(`/room/${r.platform}/${r.roomId}`); }
/** 进入分区浏览：选"全部"时先落到 B站分区，页内可再切换平台。 */
function goArea() { router.push(`/area/${platform.value === 'all' ? 'bilibili' : platform.value}`); }

watch(platform, () => load(true), { immediate: true });
</script>
