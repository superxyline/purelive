<template>
  <n-config-provider :theme="darkTheme" :theme-overrides="themeOverrides">
    <n-message-provider>
      <n-layout position="absolute">
        <n-layout-header bordered style="height: 52px; display: flex; align-items: center; padding: 0 20px; gap: 18px">
          <router-link to="/" style="text-decoration: none; font-weight: 700; font-size: 17px; color: #63e2b7">
            纯粹直播
          </router-link>
          <router-link class="nav-link" to="/">热门</router-link>
          <router-link class="nav-link" to="/follows">关注</router-link>
          <router-link class="nav-link" to="/search">搜索</router-link>
          <div style="flex: 1"></div>
          <router-link class="nav-link" to="/login">账号</router-link>
        </n-layout-header>
        <n-layout-content position="absolute" style="top: 52px" :native-scrollbar="false">
          <div style="padding: 16px 20px">
            <router-view />
          </div>
        </n-layout-content>
      </n-layout>
    </n-message-provider>
  </n-config-provider>
</template>

<script setup>
import { darkTheme } from 'naive-ui';

const themeOverrides = { common: { primaryColor: '#63e2b7' } };
</script>

<style>
body { margin: 0; background: #101014; }
.nav-link { text-decoration: none; color: #cfd0d6; font-size: 14px; padding: 4px 2px; }
.nav-link.router-link-active { color: #63e2b7; }
.room-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 14px; }
.room-card { cursor: pointer; }
.room-cover { width: 100%; height: 148px; object-fit: cover; border-radius: 6px; background: #1a1a1f; display: block; }
.room-title { font-size: 13px; margin-top: 6px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.room-sub { font-size: 12px; color: #8b8b94; display: flex; justify-content: space-between; margin-top: 2px; }
.room-plat { position: absolute; top: 6px; right: 6px; background: rgba(0,0,0,.6); color: #ddd; font-size: 11px; padding: 1px 6px; border-radius: 4px; }
.room-status { position: absolute; top: 6px; left: 6px; color: #fff; font-size: 11px; padding: 1px 6px; border-radius: 4px; }
.room-duration { position: absolute; bottom: 6px; left: 6px; background: rgba(0,0,0,.65); color: #ffd28a; font-size: 11px; padding: 1px 6px; border-radius: 4px; }
</style>
