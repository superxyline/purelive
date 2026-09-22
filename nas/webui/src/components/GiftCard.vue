<template>
  <div class="gift-card" :style="cardStyle">
    <div class="gift-icon" :style="iconStyle">
      <img v-if="giftIcon && !iconFailed" :src="giftIcon" referrerpolicy="no-referrer" alt="" @error="iconFailed = true" />
      <span v-else>{{ emoji }}</span>
    </div>
    <div class="gift-body">
      <div class="gift-user" :style="{ color: accent }">{{ userName || '观众' }}</div>
      <div class="gift-line">
        <span class="gift-sent">送出</span>
        <span class="gift-name">{{ giftName || '礼物' }}</span>
        <span class="gift-count" :key="giftCount" :style="{ color: accent }">×{{ giftCount }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue';

const props = defineProps({
  userName: { type: String, default: '' },
  giftName: { type: String, default: '' },
  giftCount: { type: Number, default: 1 },
  giftIcon: { type: String, default: '' },
  platform: { type: String, default: '' },
});

const iconFailed = ref(false);
watch(
  () => props.giftIcon,
  () => {
    iconFailed.value = false;
  },
);

/** 与安卓 _GiftPalette.fallbackFor 对齐 */
const accent = computed(() => {
  switch (props.platform) {
    case 'bilibili':
      return '#ff6b35';
    case 'douyin':
      return '#ff2c55';
    default:
      return '#ffc107';
  }
});

/** 与安卓 GiftCard._emoji 名称匹配表对齐 */
const emoji = computed(() => {
  const n = props.giftName || '';
  if (n.includes('火箭')) return '🚀';
  if (n.includes('飞机')) return '✈️';
  if (n.includes('游艇') || n.includes('游轮')) return '🛥️';
  if (n.includes('城堡')) return '🏰';
  if (n.includes('摩天轮')) return '🎡';
  if (n.includes('钻戒') || n.includes('戒指')) return '💍';
  if (n.includes('花园') || n.includes('玫瑰')) return '🌹';
  if (n.includes('情书') || n.includes('告白')) return '💌';
  if (n.includes('守护')) return '🛡️';
  if (n.includes('天使')) return '👼';
  if (n.includes('恶魔')) return '😈';
  if (n.includes('骑士') || n.includes('战士')) return '⚔️';
  if (n.includes('剑') || n.includes('刀')) return '🗡️';
  if (n.includes('锤') || n.includes('斧')) return '🔨';
  if (n.includes('枪') || n.includes('炮')) return '🔫';
  if (n.includes('炸弹') || n.includes('手雷')) return '💣';
  if (n.includes('超火') || n.includes('火焰')) return '🔥';
  if (n.includes('荧光棒') || n.includes('棒')) return '🔦';
  if (n.includes('办卡') || n.includes('卡')) return '💳';
  if (n.includes('弱鸡') || n.includes('鸡')) return '🐔';
  if (n.includes('电影票') || n.includes('电影')) return '🎬';
  if (n.includes('魔法书') || n.includes('书')) return '📖';
  if (n.includes('老虎') || n.includes('虎牙')) return '🐯';
  if (n.includes('鱼')) return '🐟';
  if (n.includes('花') || n.includes('草')) return '🌸';
  if (n.includes('星') || n.includes('星星')) return '⭐';
  if (n.includes('月') || n.includes('月亮')) return '🌙';
  if (n.includes('太阳') || n.includes('日')) return '☀️';
  if (n.includes('彩虹')) return '🌈';
  if (n.includes('皇冠')) return '👑';
  if (n.includes('钻石')) return '💎';
  if (n.includes('蛋糕') || n.includes('甜')) return '🍰';
  if (n.includes('音乐') || n.includes('音符')) return '🎵';
  if (n.includes('爱') || n.includes('心') || n.includes('❤')) return '❤️';
  return '🎁';
});

/** 安卓弹幕列表 GiftCard 普通版（非 glass）样式 */
const cardStyle = computed(() => ({
  background: `rgba(${hexToRgb(accent.value)}, 0.15)`,
  borderColor: `rgba(${hexToRgb(accent.value)}, 0.3)`,
}));

const iconStyle = computed(() => ({
  background: `rgba(${hexToRgb(accent.value)}, 0.2)`,
}));

function hexToRgb(hex) {
  const h = hex.replace('#', '');
  const n = parseInt(h, 16);
  return `${(n >> 16) & 255},${(n >> 8) & 255},${n & 255}`;
}
</script>

<style scoped>
.gift-card {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 4px 8px;
  padding: 8px 12px;
  border-radius: 6px;
  border: 1px solid;
  animation: gift-in 0.28s ease-out;
}

.gift-icon {
  flex-shrink: 0;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  font-size: 20px;
  line-height: 1;
}

.gift-icon img {
  width: 36px;
  height: 36px;
  object-fit: contain;
}

.gift-body {
  min-width: 0;
  flex: 1;
}

.gift-user {
  font-size: 13px;
  font-weight: 700;
  line-height: 1.3;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.gift-line {
  margin-top: 2px;
  font-size: 12px;
  line-height: 1.4;
  color: #adadb8;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.gift-sent {
  opacity: 0.85;
  font-weight: 400;
}

.gift-name {
  font-weight: 600;
  margin-left: 2px;
}

.gift-count {
  font-weight: 800;
  margin-left: 4px;
  font-size: 12px;
  display: inline-block;
  animation: count-pop 0.25s ease-out;
}

@keyframes gift-in {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes count-pop {
  0% {
    transform: scale(1.6);
  }
  100% {
    transform: scale(1);
  }
}
</style>
