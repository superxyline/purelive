import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  // 相对路径：file:// 本地预览与 NAS nginx 根路径部署均可
  base: './',
  server: {
    port: 5173,
    // 本地开发时把 /api 代理到 NAS 后端
    proxy: { '/api': { target: 'http://192.168.31.26:8090', changeOrigin: true } },
  },
  build: {
    chunkSizeWarningLimit: 1500,
    // 独立目录名，避免与 Flutter assets/ 资源目录冲突
    assetsDir: 'static',
  },
});
