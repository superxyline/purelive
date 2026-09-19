import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    // 本地开发时把 /api 代理到 NAS 后端
    proxy: { '/api': { target: 'http://192.168.31.26:8090', changeOrigin: true } },
  },
  build: { chunkSizeWarningLimit: 1500 },
});
