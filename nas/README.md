# Pure Live NAS 网页端部署

一键部署纯 Web 版纯粹直播：Vue3 + Naive UI 前端 + Node 聚合后端（API 代理/取流签名/弹幕代理/登录托管）。

## 架构

```
浏览器 ──> nginx(web 容器)
             ├── /            WebUI 静态资源（nas/webui 构建产物）
             └── /api ──────> server 容器（Node/Fastify）
                  ├── /api/sites/:p/...   五平台 API 聚合（B站 WBI、斗鱼 ub98484234、抖音 a-bogus、虎牙 anticode 签名在服务端执行）
                  ├── /api/danmaku/:p/:roomId  弹幕 WebSocket 代理（B站 brotli、斗鱼 STT、虎牙 Tars、抖音 protobuf → 统一 JSON）
                  ├── /api/auth/...       B站扫码登录 + 各平台 cookie 托管（AES-256-GCM 加密落盘）
                  ├── /api/stream/proxy   直播流 Referer 校验时的回退代理
                  ├── /api/sync/data      App↔NAS 关注+屏蔽三件套同步（WebUI 用 /api/sync/follows）
                  └── /api/discover       局域网自动发现（App 扫描网段后取服务信息）
```

## 部署（Docker Compose，一条命令）

前置只需要装好 Docker + Compose 插件，**不需要在宿主机装 Node，也不需要先构建前端**——镜像内会分三段自动完成：vite 构建 WebUI → tsc 编译 server → 只带生产依赖的运行时。

```bash
cd nas/deploy
cp .env.example .env        # 可选：改端口/令牌/镜像源
docker compose up -d --build
```

浏览器打开 `http://<主机IP>:8090`（端口在 `.env` 的 `PORT` 里改）。

- 想改端口/开访问令牌/注入平台 Cookie：都在 `nas/deploy/.env` 里，改完 `docker compose up -d` 生效（密钥类变量需 `--force-recreate`）。
- 国内网络默认用 `npmmirror` 拉 npm 依赖；海外可把 `NPM_REGISTRY` 改成 `https://registry.npmjs.org`。
- 拉不动基础镜像时，把 `Dockerfile` 顶部的 `ARG NODE_IMAGE=node:20-alpine` 换成 NAS 上已有的版本（如 `node:22-alpine`）。
- 用户不在 docker 组时命令前加 `sudo`。

### 常用运维命令

```bash
docker compose logs -f            # 看日志
docker compose ps                 # 看状态（含 healthcheck）
docker compose pull && docker compose up -d --build   # 更新代码后重建
docker compose down               # 停止（数据保留在 ./data）
```

### 数据与备份

| 内容 | 位置 | 说明 |
|---|---|---|
| 托管登录态 `cookies.enc` | `nas/deploy/data/cookies.enc` | AES-256-GCM，密钥见同目录 `.masterkey` 或 `.env` 的 `NAS_MASTER_KEY` |
| 主密钥 | `nas/deploy/data/.masterkey`（或环境变量） | **迁移机器必须一起带走**，否则已托管 Cookie 无法解密 |
| 关注/屏蔽同步 | `nas/deploy/data/synced.json` | App「推送到 NAS」写入 |
| 日志 | 容器 stdout | `docker compose logs` 查看，已限制 10MB×3 轮转 |

备份 = 直接拷 `nas/deploy/data/` 整个目录；恢复 = 放回同位置再 `up -d`。

### 架构（单容器）

```
浏览器 ──> purelive 容器（Node/Fastify，端口 8080 → 宿主机 8090）
             ├── /             WebUI 静态资源（镜像内 vite 构建，SPA 回退）
             ├── /api/sites/:p/...          五平台 API 聚合（B站 WBI、斗鱼 ub98484234、抖音 a-bogus、虎牙 anticode 签名在服务端执行）
             ├── /api/danmaku/:p/:roomId    弹幕 WebSocket 代理（B站 brotli、斗鱼 STT、虎牙 Tars、抖音 protobuf → 统一 JSON）
             ├── /api/auth/...              B站扫码登录 + 各平台 cookie 托管（AES-256-GCM 加密落盘）
             ├── /api/stream/proxy          直播流 Referer 校验时的回退代理
             ├── /api/sync/data             App↔NAS 关注+屏蔽三件套同步（WebUI 用 /api/sync/follows）
             ├── /api/discover              局域网自动发现（App 扫描网段后取服务信息）
             └── /api/health                健康检查（容器 healthcheck 用的就是这个）
```

> 想保留「nginx 静态 + server 独立容器」的老架构，用 `docker-compose.nginx.yml`（需宿主自行 `npm run build` 并把产物覆盖到 `nas/webui-dist/`），见该文件头部注释。

### 前端开发调试

```bash
cd nas/webui && npm run dev     # 5173 端口，/api 代理到本机 8090
```

### 飞牛 fnOS 原生应用（fpk，免 Docker）

飞牛用户可不装 Docker：应用中心「手动安装」上传 [`nas/fnos/purelive.fpk`](fnos/)（约 39MB，内置 Linux Node20 运行时与全部生产依赖），装完桌面点 **Pure Live** 图标打开 `http://<NAS-IP>:8090`。

- 数据（加密 cookie、关注同步、日志）落在应用数据目录 `var/data/`，卸载应用也保留；备份即拷该目录；
- 可选访问令牌：数据目录 `env` 文件里 `PURE_LIVE_TOKEN=` 填值后在应用中心重启生效（对应下文 WebUI 令牌弹窗 / `x-api-token` 头）；
- 应用以独立包用户 `purelive` 运行，仅写自己的数据目录；启停用应用中心按钮（端口 8090，被占用会装不上）；
- 自行打包：`bash nas/fnos/build_fpk.sh`（组装 server/webui 产物 → 下载 node 运行时 → fnpack → repack 移动端图标）。

## 登录与发弹幕（可选）

Web 端默认只读观看。需要 B站发弹幕时：

1. 打开应用内登录页扫码（后端代理 passport.bilibili.com，cookie 自动托管到 NAS）；
2. 其他平台可在 `POST /api/auth/<platform>` 提交 cookie 串（或在应用设置里粘贴）。

托管了 cookie 的平台，**取流请求会一并带上登录态**（斗鱼尤其重要：匿名会话下 `原画1080P60` 会被服务端降成 `1080p30 / 4Mbps`）。
App 端「推送到 NAS」会把关注、弹幕屏蔽与各平台登录 cookie 一起推过来，落盘后**立即生效**，无需重启容器。

## 环境变量（server 容器）

| 变量 | 默认 | 说明 |
|---|---|---|
| `NAS_MASTER_KEY` | 自动生成 | cookie 加密主密钥（≥16 字符，建议设置并保存） |
| `PURE_LIVE_COOKIE_*` | — | 各平台 cookie 的环境变量注入方式（大写平台名，如 `PURE_LIVE_COOKIE_BILIBILI`） |
| `PURE_LIVE_TOKEN` | 不设 | API 访问令牌（公网部署必设；WebUI 401 弹窗录入 / REST `x-api-token` 头 / WS `?token=`） |
| `PURE_LIVE_DATA_DIR` | `<cwd>/../data` | 数据目录（fpk 指向 `TRIM_PKGVAR/data`，便携版指向包内 `data/`） |
| `PURE_LIVE_WEBUI_DIR` | 不设（走 nginx） | 由 server 直接托管 WebUI 静态文件（fpk / 便携版用；含 SPA 回退） |
| `LOG_LEVEL` | info | 日志级别 |

## 局域网与安全提示

- 建议**仅在局域网内使用**；暴露公网时务必配置反向代理 HTTPS + 访问控制（cookie 托管在 NAS 上，等于把账号交给部署者）。
- `data/` 目录包含加密后的 cookie，请纳入 NAS 备份并限制访问权限。

## 注意事项

- B站 HEVC 编码在部分浏览器不支持硬解，Web 端取流默认 AVC 优先。
- B站分区房间列表接口（`second/getList`）对无登录态的请求可能返回 -352 风控，托管有效 cookie 后恢复。
- 安卓客户端与 Web 端共用同一仓库构建，互不影响。
