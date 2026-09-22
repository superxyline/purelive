<template>
  <div>
    <n-select v-model:value="platform" :options="platformOptions" style="max-width: 220px; margin-bottom: 14px" />
    <n-spin :show="loading">
      <n-tabs type="line" v-model:value="cateId" @update:value="onCateChange">
        <n-tab v-for="c in categories" :key="c.id" :name="c.id">{{ c.name }}</n-tab>
      </n-tabs>
      <n-select v-if="subOptions.length" v-model:value="subName" size="small" :options="subOptions" style="max-width: 240px; margin: 10px 0" placeholder="选择子分区" @update:value="loadRooms" />
      <n-empty v-if="!loading && rooms.length === 0" description="该分区暂无直播间" style="margin: 60px 0" />
      <div v-else class="room-grid">
        <div v-for="r in rooms" :key="r.roomId" class="room-card" @click="$router.push(`/room/${r.platform}/${r.roomId}`)">
          <img class="room-cover" :src="r.cover" referrerpolicy="no-referrer" loading="lazy" @error="$event.target.style.opacity = 0" />
          <div class="room-title">{{ r.title }}</div>
          <div class="room-sub"><span>{{ r.nick }}</span><span>🔥 {{ r.watching || r.popularity }}</span></div>
        </div>
      </div>
    </n-spin>
  </div>
</template>

<script setup>
import { ref, watch, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { api, PLATFORMS } from '../api';

const route = useRoute();
const router = useRouter();
const routePlatform = computed(() => route.params.platform);
const platform = ref(routePlatform.value);
const categories = ref([]);
const cateId = ref('');
const subName = ref(null); // 当前选中的子分区 areaId（不是名称）
const rooms = ref([]);
const loading = ref(false);

const platformOptions = PLATFORMS.map((p) => ({ label: p.name, value: p.id }));
const subCates = computed(() => categories.value.find((c) => c.id === cateId.value)?.children || []);
/**
 * value 必须是子分区 areaId：后端五个平台都按"子分区 id"取流
 *（斗鱼 mixList/2_{id}、虎牙 gameId、B站 area_id、抖音 partition、快手 gameId），
 * 传顶层分类 id 会取到不相干的房间（斗鱼顶层"娱乐天地"的 id=2 恰好是炉石传说的 areaId）。
 */
const subOptions = computed(() => subCates.value.map((c) => ({ label: c.areaName, value: c.areaId })));

async function loadCategories() {
  loading.value = true;
  try {
    categories.value = await api.categories(platform.value);
    if (categories.value.length) { cateId.value = categories.value[0].id; onCateChange(cateId.value); }
  } catch (e) { window.$msg.error(String(e.message || e)); }
  loading.value = false;
}

async function onCateChange(id) {
  // 每个分类默认落到它的第一个子分区（后端需要具体的子分区 id 才能取到对应房间）
  subName.value = categories.value.find((c) => c.id === id)?.children?.[0]?.areaId ?? '';
  await loadRooms();
}

async function loadRooms() {
  loading.value = true;
  rooms.value = [];
  try {
    const cate = categories.value.find((c) => c.id === cateId.value);
    const areaId = subName.value || cate?.children?.[0]?.areaId || cateId.value;
    const areaName = cate?.children?.find((c) => c.areaId === areaId)?.areaName ?? cate?.name ?? '';
    rooms.value = await api.categoryRooms(platform.value, areaId, areaName);
  } catch (e) {
    window.$msg.error(String(e.message || e));
  }
  loading.value = false;
}

watch(platform, (v) => {
  cateId.value = '';
  categories.value = [];
  // URL 跟随所选平台，便于分享与刷新后保持
  router.replace(`/area/${v}`);
  loadCategories();
});
watch(() => routePlatform.value, (v) => { platform.value = v; });
loadCategories();
</script>
