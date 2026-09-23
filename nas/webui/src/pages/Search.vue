<template>
  <div>
    <div style="display: flex; gap: 12px; margin-bottom: 14px; max-width: 720px; align-items: center">
      <n-button-group size="small">
        <n-button :type="searchType === 'rooms' ? 'primary' : 'default'" @click="searchType = 'rooms'">搜直播间</n-button>
        <n-button :type="searchType === 'anchors' ? 'primary' : 'default'" @click="searchType = 'anchors'">搜主播</n-button>
      </n-button-group>
      <n-select v-model:value="platform" :options="platformOptions" style="width: 140px" />
      <n-input v-model:value="keyword" placeholder="搜索直播间 / 主播，回车搜索" @keyup.enter="doSearch" />
      <n-button type="primary" :loading="loading" @click="doSearch">搜索</n-button>
    </div>
    <div v-if="skipped.length" class="skip-hint">
      已跳过搜索失败的平台：{{ skipped.join('、') }}
    </div>
    <n-empty
      v-if="!loading && searched && rooms.length === 0"
      :description="searchType === 'anchors' ? '没有找到相关主播' : '没有找到相关直播间'"
      style="margin: 60px 0"
    />
    <!-- 主播搜索结果（头像卡片） -->
    <div v-else-if="searchType === 'anchors'" class="room-grid">
      <div
        v-for="a in rooms"
        :key="a.platform + a.roomId + a.nick"
        class="room-card"
        @click="goAnchor(a)"
      >
        <div style="position: relative">
          <img class="room-cover" :src="a.avatar || a.cover" referrerpolicy="no-referrer" loading="lazy" @error="$event.target.style.opacity = 0" />
          <span v-if="a.liveStatus === 0" class="room-status is-live">直播中</span>
          <span v-else class="room-status is-offline">未开播</span>
          <span v-if="platform === 'all'" class="room-plat">{{ platformName(a.platform) }}</span>
        </div>
        <div class="room-title">{{ a.nick }}</div>
        <div class="room-sub"><span>{{ a.title || '点击进入直播间' }}</span></div>
      </div>
    </div>
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
import { useRouter } from 'vue-router';
import { api, PLATFORMS } from '../api';

const router = useRouter();

function goAnchor(a) {
  if (a.roomId) router.push(`/room/${a.platform}/${a.roomId}`);
  else window.$msg.warning('该主播暂无直播间');
}

const platform = ref('all');
const keyword = ref('');
const rooms = ref([]);
const loading = ref(false);
const searched = ref(false);
const page = ref(1);
const skipped = ref([]);
const searchType = ref('rooms'); // rooms=搜直播间 | anchors=搜主播（后端 anchors 五平台：B站/斗鱼/虎牙可用，抖音 throw、快手空）

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
  const searchFn = searchType.value === 'anchors' ? api.searchAnchors : api.search;
  const results = await Promise.all(
    PLATFORMS.map((p) =>
      searchFn(p.id, keyword.value, page.value)
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
      const searchFn = searchType.value === 'anchors' ? api.searchAnchors : api.search;
      rooms.value.push(...(await searchFn(platform.value, keyword.value, page.value)));
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

// 切换平台/搜索类型后旧结果不再适用，清空等用户重新搜索
watch([platform, searchType], () => {
  rooms.value = [];
  searched.value = false;
  skipped.value = [];
});
</script>
