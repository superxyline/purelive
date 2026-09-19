<template>
  <div>
    <n-select v-model:value="platform" :options="platformOptions" style="max-width: 220px; margin-bottom: 14px" />
    <n-spin :show="loading">
      <n-tabs type="line" v-model:value="cateId" @update:value="onCateChange">
        <n-tab v-for="c in categories" :key="c.id" :name="c.id">{{ c.name }}</n-tab>
      </n-tabs>
      <n-select v-if="subCates.length > 1" v-model:value="subName" size="small" :options="subOptions" style="max-width: 220px; margin: 10px 0" placeholder="全部分区" clearable />
      <n-empty v-if="!loading && rooms.length === 0" description="该分区暂无直播间" style="margin: 60px 0" />
      <div v-else class="room-grid">
        <div v-for="r in rooms" :key="r.roomId" class="room-card" @click="$router.push(`/room/${r.platform}/${r.roomId}`)">
          <img class="room-cover" :src="r.cover" loading="lazy" @error="$event.target.style.opacity = 0" />
          <div class="room-title">{{ r.title }}</div>
          <div class="room-sub"><span>{{ r.nick }}</span><span>🔥 {{ r.watching || r.popularity }}</span></div>
        </div>
      </div>
    </n-spin>
  </div>
</template>

<script setup>
import { ref, watch, computed } from 'vue';
import { useRoute } from 'vue-router';
import { api, PLATFORMS } from '../api';

const routePlatform = computed(() => route.params.platform);
const route = useRoute();
const platform = ref(routePlatform.value);
const categories = ref([]);
const cateId = ref('');
const subName = ref(null);
const rooms = ref([]);
const loading = ref(false);

const platformOptions = PLATFORMS.map((p) => ({ label: p.name, value: p.id }));
const subCates = computed(() => categories.value.find((c) => c.id === cateId.value)?.children || []);
const subOptions = computed(() => subCates.value.map((c) => ({ label: c.areaName, value: c.areaName })));

async function loadCategories() {
  loading.value = true;
  try {
    categories.value = await api.categories(platform.value);
    if (categories.value.length) { cateId.value = categories.value[0].id; onCateChange(cateId.value); }
  } catch (e) { window.$msg.error(String(e.message || e)); }
  loading.value = false;
}

async function onCateChange(id) {
  subName.value = null;
  await loadRooms();
}

async function loadRooms() {
  loading.value = true;
  rooms.value = [];
  try {
    const cate = categories.value.find((c) => c.id === cateId.value);
    rooms.value = await api.categoryRooms(platform.value, cateId.value, subName.value || cate?.name || '');
  } catch (e) {
    window.$msg.error(String(e.message || e));
  }
  loading.value = false;
}

watch(platform, () => { cateId.value = ''; categories.value = []; loadCategories(); });
watch(() => routePlatform.value, (v) => { platform.value = v; });
watch(subName, () => loadRooms());
loadCategories();
</script>
