import { createApp } from 'vue';
import { createRouter, createWebHistory } from 'vue-router';
import naive, { createDiscreteApi } from 'naive-ui';
import App from './App.vue';
import Home from './pages/Home.vue';
import Area from './pages/Area.vue';
import Search from './pages/Search.vue';
import Room from './pages/Room.vue';
import Login from './pages/Login.vue';
import Follows from './pages/Follows.vue';

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: Home },
    { path: '/area/:platform', component: Area },
    { path: '/search', component: Search },
    { path: '/room/:platform/:roomId', component: Room },
    { path: '/login', component: Login },
    { path: '/follows', component: Follows },
  ],
});

// 离散消息 API：非 setup 上下文也能弹提示
window.$msg = createDiscreteApi(['message']).message;

createApp(App).use(naive).use(router).mount('#app');
