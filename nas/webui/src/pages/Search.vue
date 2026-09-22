<template>
  <div>
    <div style="display: flex; gap: 12px; margin-bottom: 14px; max-width: 620px">
      <n-select v-model:value="platform" :options="platformOptions" style="width: 150px" />
      <n-input v-model:value="keyword" placeholder="搜索直播间 / 主播，回车搜索" @keyup.enter="doSearch" />
      <n-button type="primary" :loading="loading" @click="doSearch">搜索</n-button>
    </div>
    <div v-if="skipped.length" class="skip-hint">
      已跳过搜索失败的平台：{{ skipped.join('、') }}
    </div>
    <n-empty v-if="!loading && searched && rooms.length === 0" description="没有找到相关直播间" style="margin: 60px 0" />
    <div v-else class="room-grid">
      <div v-for="r in rooms" :key="r.platform + r.roomId" class="room-card" @click="$router.push(`/room/${r.platform}/${r.roomId}`)">
        <div style="position: relative">
          <img class="room-cover" :src="r.cover" referrerpolicy="no-referrer" loading="lazy" @error="$event.target.style.opacity = 0" />
          <span v-if="platform === 'all'" class="room-plat">{{ platformName(r.platform) }}</span>
        </div>
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
import { ref, watch } from 'vue';
import { api, PLATFORMS } from '../api';

const platform = ref('all');
const keyword = ref('');
const rooms = ref([]);
const loading = ref(false);
const searched = ref(false);
const page = ref(1);
const skipped = ref([]);

const platformOptions = [
  { label: '全部平台', value: 'all' },
  ...PLATFORMS.map((p) => ({ label: p.name, value: p.id })),
];
const platformName = (id) => PLATFORMS.find((p) => p.id === id)?.name || id;

async function doSearch() {
  if (!keyword.value.trim()) return;
  page.value = 1;
  rooms.value = [];
  searched.value = true;
  await load();
}

/** 全平台：并发搜索后交错合并，个别平台失败（如抖音需登录）只跳过并列出。 */
async function loadAll() {
  const results = await Promise.all(
    PLATFORMS.map((p) =>
      api
        .search(p.id, keyword.value, page.value)
        .then((data) => ({ id: p.id, data }))
        .catch(() => ({ id: p.id, data: null })),
    ),
  );
  skipped.value = results.filter((r) => r.data === null).map((r) => platformName(r.id));
  const merged = [];
  const maxLen = Math.max(...results.map((r) => (r.data ? r.data.length : 0)), 0);
  for (let i = 0; i < maxLen; i++) {
    for (const r of results) {
      if (r.data && r.data[i]) merged.push(r.data[i]);
    }
  }
  rooms.value.push(...merged);
}

async function load() {
  loading.value = true;
  try {
    if (platform.value === 'all') {
      await loadAll();
    } else {
      skipped.value = [];
      rooms.value.push(...(await api.search(platform.value, keyword.value, page.value)));
    }
  } catch (e) {
    window.$msg.error(String(e.message || e));
  }
  loading.value = false;
}

function loadMore() {
  page.value += 1;
  load();
}

// 切换平台后旧结果不再适用，清空等用户重新搜索
watch(platform, () => {
  rooms.value = [];
  searched.value = false;
  skipped.value = [];
});
</script>
