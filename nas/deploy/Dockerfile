# Pure Live 全栈镜像：一个容器同时提供 WebUI 静态资源 + /api 聚合后端。
#
# 构建上下文是**仓库根目录**（见 docker-compose.yml 的 context: ../..），
# 这样一次 docker compose up --build 就能在镜像内完成前端与后端构建，
# 宿主机不需要装 Node、也不需要手动 npm run build。
#
#   stage 1  webui   : vite 构建 Vue 前端
#   stage 2  server  : tsc 编译 Fastify 后端
#   stage 3  runtime : 只带生产依赖 + 两份产物，非 root 运行
#
# 国内镜像源：默认走 npmmirror，构建时可用
#   docker compose build --build-arg NPM_REGISTRY=https://registry.npmjs.org
# 切回官方源。

ARG NODE_IMAGE=node:20-alpine

# ---------------------------------------------------------------- 前端构建
FROM ${NODE_IMAGE} AS webui
ARG NPM_REGISTRY=https://registry.npmmirror.com
WORKDIR /app
COPY nas/webui/package.json nas/webui/package-lock.json* ./
RUN npm ci --registry=${NPM_REGISTRY} || npm install --registry=${NPM_REGISTRY}
COPY nas/webui/ ./
RUN npm run build

# ---------------------------------------------------------------- 后端编译
FROM ${NODE_IMAGE} AS server
ARG NPM_REGISTRY=https://registry.npmmirror.com
WORKDIR /app
COPY nas/server/package.json nas/server/package-lock.json* ./
RUN npm ci --registry=${NPM_REGISTRY} || npm install --registry=${NPM_REGISTRY}
COPY nas/server/tsconfig.json ./
COPY nas/server/src ./src
RUN ./node_modules/.bin/tsc

# ---------------------------------------------------------------- 运行时
FROM ${NODE_IMAGE}
ARG NPM_REGISTRY=https://registry.npmmirror.com
WORKDIR /app
ENV NODE_ENV=production \
    PORT=8080 \
    PURE_LIVE_DATA_DIR=/app/data \
    PURE_LIVE_WEBUI_DIR=/app/webui

COPY nas/server/package.json nas/server/package-lock.json* ./
RUN npm ci --omit=dev --registry=${NPM_REGISTRY} || npm install --omit=dev --registry=${NPM_REGISTRY} \
    && npm cache clean --force

COPY --from=server /app/dist ./dist
COPY --from=webui /app/dist ./webui

# bind mount 进来的宿主目录通常属于 root，直接以 node 启动会写不了数据；
# 入口脚本负责「chown 数据目录 → su-exec 降权」，进程本身仍非 root。
RUN apk add --no-cache su-exec \
    && mkdir -p /app/data \
    && chown -R node:node /app /app/data
COPY --chmod=755 nas/deploy/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

EXPOSE 8080

# 容器的健康判据就是 /api/health，编排层与 NAS 面板都能直接读
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["node", "dist/index.js"]
