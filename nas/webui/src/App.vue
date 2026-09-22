<template>
  <n-config-provider :theme="darkTheme" :theme-overrides="themeOverrides">
    <n-message-provider>
      <n-layout position="absolute" class="tw-shell">
        <n-layout-header bordered class="tw-header">
          <router-link to="/" class="tw-logo">纯粹直播</router-link>
          <router-link class="nav-link" :class="{ 'nav-on': isOn('/') }" to="/">热门</router-link>
          <router-link class="nav-link" :class="{ 'nav-on': isOn('/area') }" to="/area/bilibili">分区</router-link>
          <router-link class="nav-link" :class="{ 'nav-on': isOn('/follows') }" to="/follows">关注</router-link>
          <router-link class="nav-link" :class="{ 'nav-on': isOn('/search') }" to="/search">搜索</router-link>
          <div style="flex: 1"></div>
          <router-link class="nav-link" :class="{ 'nav-on': isOn('/login') }" to="/login">账号</router-link>
        </n-layout-header>
        <n-layout-content position="absolute" style="top: 52px" :native-scrollbar="false">
          <div class="tw-page">
            <router-view />
          </div>
        </n-layout-content>
      </n-layout>
    </n-message-provider>
  </n-config-provider>
</template>

<script setup>
import { darkTheme } from 'naive-ui';
import { useRoute } from 'vue-router';

const route = useRoute();

/** Twitch 结构 + 天蓝主色（仅覆盖视觉 token） */
const themeOverrides = {
  common: {
    primaryColor: '#38bdf8',
    primaryColorHover: '#0ea5e9',
    primaryColorPressed: '#0284c7',
    primaryColorSuppl: '#38bdf8',
    borderRadius: '6px',
    borderRadiusSmall: '4px',
    fontFamily: '"Inter", "Segoe UI", "PingFang SC", "Microsoft YaHei", system-ui, sans-serif',
    bodyColor: '#0e0e10',
    cardColor: '#18181b',
    modalColor: '#18181b',
    popoverColor: '#18181b',
    inputColor: '#18181b',
    actionColor: '#18181b',
    hoverColor: 'rgba(56, 189, 248, 0.12)',
    borderColor: '#2a2a2d',
    dividerColor: '#2a2a2d',
    textColorBase: '#efeff1',
    textColor1: '#efeff1',
    textColor2: '#adadb8',
    textColor3: '#8b8b94',
    placeholderColor: '#8b8b94',
    iconColor: '#adadb8',
  },
  Button: {
    fontWeight: '600',
    fontWeightStrong: '700',
  },
  Card: {
    borderRadius: '12px',
    borderColor: '#2a2a2d',
    titleFontSizeMedium: '15px',
  },
  Tabs: {
    tabColorActiveLine: '#38bdf8',
    tabTextColorActiveLine: '#efeff1',
    tabTextColorHoverLine: '#efeff1',
    tabTextColorActiveSegment: '#ffffff',
    colorSegment: '#18181b',
  },
  Tag: {
    borderRadius: '999px',
  },
};

/** 导航高亮：'/' 必须精确匹配（否则会匹配所有路径），其余按前缀匹配。 */
const isOn = (prefix) => (prefix === '/' ? route.path === '/' : route.path.startsWith(prefix));
</script>

<style>
@import './styles/twitch.css';

.tw-page {
  padding: 16px 24px 24px;
}
</style>
