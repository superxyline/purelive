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

## 部署

```bash
cd nas/deploy
docker compose up -d --build
```

浏览器访问 `http://<NAS-IP>:8090`（推荐）或 `https://<NAS-IP>:8091`（自签证书，首次需信任）。

> 前端为 `nas/webui`（Vue3 + Naive UI）。开发调试：`cd nas/webui && npm run dev`；构建：`npm run build`，把产物 `dist/` 的内容覆盖到 NAS 的 `webui-dist/` 即可（内容覆盖，不要删除目录本身），无需重启 nginx。

### 无公网镜像源的 NAS（飞牛 fnOS 等）实测备注

- web 容器直接用 `nginx:1.27-alpine` 挂载前端构建产物（见 `nas/deploy/docker-compose.yml`），不需要在镜像里构建前端。
- 拉取 `node:20-alpine` 失败时，改用 NAS 上已有的镜像（如 `node:22-alpine`，只改 Dockerfile 的 FROM 即可）。
- 用户不在 docker 组时用 `sudo docker compose up -d --build`。
- 替换 nginx.conf 后必须 `sudo docker compose up -d --force-recreate web`（单文件 bind mount 改动后容器内仍是旧 inode，reload 不生效）。

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
