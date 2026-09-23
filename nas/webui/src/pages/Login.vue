<template>
  <div style="max-width: 520px; margin: 0 auto">
    <n-card title="B站扫码登录">
      <template #header-extra>
        <div style="display: flex; gap: 8px; align-items: center">
          <n-tag size="small" :type="biliLogged ? 'success' : 'default'">{{ biliLogged ? '已登录' : '未登录' }}</n-tag>
          <n-button v-if="biliLogged" size="tiny" quaternary type="error" @click="logout('bilibili')">退出登录</n-button>
        </div>
      </template>
      <div style="text-align: center">
        <div v-if="!qrUrl" style="padding: 30px 0">
          <n-button type="primary" @click="genQr" :loading="qrLoading">生成登录二维码</n-button>
        </div>
        <template v-else>
          <canvas ref="qrCanvas" style="width: 200px; height: 200px; background: #fff; border-radius: 8px; padding: 8px"></canvas>
          <div style="margin-top: 10px; font-size: 13px">{{ qrStatusText }}</div>
          <n-button quaternary size="small" style="margin-top: 6px" @click="genQr">刷新二维码</n-button>
        </template>
        <div v-if="biliName" style="margin-top: 10px; color: #7dd3fc">当前账号：{{ biliName }}</div>
      </div>
    </n-card>

    <n-card title="其他平台 Cookie 登录" style="margin-top: 16px">
      <n-tabs type="line" v-model:value="cookiePlatform">
        <n-tab v-for="p in platforms" :key="p" :name="p">{{ { douyu: '斗鱼', huya: '虎牙', douyin: '抖音', kuaishou: '快手' }[p] }}</n-tab>
      </n-tabs>
      <n-input v-model:value="cookieInput" type="textarea" :rows="3" placeholder="粘贴浏览器里复制的 Cookie 字符串" style="margin: 10px 0" />
      <n-button type="primary" @click="saveCookieBtn" :loading="saving">保存 Cookie</n-button>
      <n-button
        v-if="authSt[cookiePlatform]"
        quaternary
        type="error"
        size="small"
        style="margin-left: 8px"
        @click="logout(cookiePlatform)"
      >清除该平台登录</n-button>
      <div v-if="authSt[cookiePlatform]" style="font-size: 12px; color: #8b8b94; margin-top: 8px">该平台已有托管的登录态</div>
    </n-card>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted, nextTick } from 'vue';
import QRCode from 'qrcode';
import { api } from '../api';

const biliLogged = ref(false);
const biliName = ref('');
const qrUrl = ref('');
const qrCanvas = ref(null);
const authSt = ref({}); // 各平台托管登录态（GET /api/auth/status）
const qrStatusText = ref('请用哔哩哔哩 App 扫码');
const qrLoading = ref(false);
let qrKey = '';
let pollTimer = null;

const platforms = ['douyu', 'huya', 'douyin', 'kuaishou'];
const cookiePlatform = ref('douyu');
const cookieInput = ref('');
const saving = ref(false);

async function refreshStatus() {
  try {
    const st = await api.authStatus();
    authSt.value = st;
    biliLogged.value = !!st.bilibili;
    const s = await api.bilibiliSession();
    if (s.ok) { biliName.value = s.uname; biliLogged.value = true; }
  } catch (_) {}
}

async function logout(p) {
  try {
    const r = await api.clearAuth(p);
    if (r.ok) {
      window.$msg.success('已清除该平台登录态');
      if (p === 'bilibili') { biliLogged.value = false; biliName.value = ''; qrUrl.value = ''; }
      await refreshStatus();
    }
  } catch (e) {
    window.$msg.error('清除失败: ' + e.message);
  }
}

async function genQr() {
  qrLoading.value = true;
  qrUrl.value = '';
  qrStatusText.value = '请用哔哩哔哩 App 扫码';
  try {
    const d = await api.bilibiliQr();
    qrKey = d.qrcode_key;
    qrUrl.value = d.url;
    // canvas 在 v-if 下刚进入 DOM，必须等渲染后再画
    await nextTick();
    await QRCode.toCanvas(qrCanvas.value, d.url, { width: 184, margin: 0 });
    startPoll();
  } catch (e) { window.$msg.error(String(e.message || e)); }
  qrLoading.value = false;
}

function startPoll() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = setInterval(async () => {
    try {
      const r = await api.bilibiliPoll(qrKey);
      const code = r.data?.code;
      if (code === 0) {
        clearInterval(pollTimer);
        qrStatusText.value = '登录成功！Cookie 已托管到 NAS';
        await refreshStatus();
        window.$msg.success('B站登录成功');
      } else if (code === 86090) { qrStatusText.value = '已扫码，请在手机上确认'; }
      else if (code === 86038) { clearInterval(pollTimer); qrStatusText.value = '二维码已过期，请刷新'; }
    } catch (_) {}
  }, 2500);
}

async function saveCookieBtn() {
  if (!cookieInput.value.trim()) return window.$msg.warning('请先粘贴 Cookie');
  saving.value = true;
  const r = await api.saveCookie(cookiePlatform.value, cookieInput.value.trim());
  saving.value = false;
  window.$msg[r.ok ? 'success' : 'error'](r.ok ? 'Cookie 已保存' : '保存失败');
  if (r.ok) cookieInput.value = '';
}

onMounted(refreshStatus);
onUnmounted(() => { if (pollTimer) clearInterval(pollTimer); });
</script>
