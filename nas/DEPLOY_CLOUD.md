# 云服务器部署指南

把 Pure Live 服务端部署到公网云服务器（阿里云/腾讯云/AWS 等），任何设备的浏览器都能访问。
**与 NAS 部署共用同一套 Docker 化产物，区别只在网络暴露与安全配置。**

## 部署方式一：Docker Compose（推荐）

前置：云服务器已安装 Docker 与 Docker Compose（docker compose version 可查）。

```bash
# 1. 拉取代码
git clone https://gitee.com/superxyline/purelive.git && cd purelive/nas

# 2. 构建前端产物（本机或服务器上执行，需要 Node 20+）
cd webui && npm ci && npm run build && cd ..
mkdir -p webui-dist && cp -r webui/dist/* webui-dist/

# 3. 生成访问令牌（必设！公网必须保护托管的平台登录 Cookie）
echo "PURE_LIVE_TOKEN=$(head -c 24 /dev/urandom | base64)" > .env

# 4. 启动
docker compose up -d --build
```

访问 `http://<服务器公网IP>:8090`，页面加载后弹出令牌输入框，粘贴 `.env` 里的
`PURE_LIVE_TOKEN` 值即可（存浏览器 localStorage，之后不再询问）。

> compose 里 server 服务默认已预留 `PURE_LIVE_TOKEN` 注释项，用 `.env` 注入或
> 手动取消注释填值均可。

## 部署方式二：裸机 + systemd（不装 Docker）

```bash
# 依赖：Node 20+ 与 nginx（或 caddy）
git clone https://gitee.com/superxyline/purelive.git && cd purelive/nas
cd server  && npm ci && npm run build
cd ../webui && npm ci && npm run build

# systemd 服务
sudo tee /etc/systemd/system/purelive.service <<'EOF'
[Unit]
Description=Pure Live server
After=network.target
[Service]
WorkingDirectory=/opt/purelive/nas/server
Environment=PORT=8080
Environment=PURE_LIVE_TOKEN=改成你的随机令牌
# 数据目录（关注同步、平台 Cookie 加密存储），按需修改
Environment=PURE_LIVE_DATA_DIR=/opt/purelive/data
ExecStart=/usr/bin/node dist/index.js
Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now purelive
```

前端静态文件用 nginx/caddy 托管并反代 `/api/`（参考 `deploy/nginx.conf`，
把 `proxy_pass http://server:8080` 改为 `http://127.0.0.1:8080`）；
或直接设 `PURE_LIVE_WEBUI_DIR=/opt/purelive/nas/webui/dist` 让 server 自托管，
省掉 nginx（仅 HTTP，建议前面再放一层 caddy 做 HTTPS）。

## 安全清单（公网部署必读）

1. **必须设置 `PURE_LIVE_TOKEN`**：服务端托管的各平台登录 Cookie、弹幕发送、
   关注数据都在 `/api/*` 后面，没有令牌等于对全网开放你的身份。
   令牌长度建议 ≥24 位随机字符串；WebUI 首次访问弹窗录入一次即可。
2. **启用 HTTPS**：登录 Cookie 与令牌经公网明文传输有被嗅探风险。最省事的方案是
   [caddy](https://caddyserver.com/)（自动签发 Let's Encrypt 证书）反代 8090：
   有域名时 `yourdomain.com { reverse_proxy 127.0.0.1:8090 }` 两行配置即可。
3. **防火墙只放行必要端口**：80/443（对外），22（SSH，建议改端口/密钥登录）。
   8090 可不对公网开放（由反代转发）。
4. `NAS_MASTER_KEY`（平台 Cookie 落盘加密密钥）同样建议设置：数据目录泄露时
   Cookie 仍是密文。
5. 不需要手机 App 连服务时，不要把 8090 暴露到公网。

## 与 NAS / Windows 便携版的差异

| 项 | NAS | 云服务器 | Windows 便携版 |
| --- | --- | --- | --- |
| 运行形态 | Docker Compose | Docker 或 systemd | 双击 启动.bat |
| 访问令牌 | 可不设（局域网） | **必设** | 可不设（本机） |
| HTTPS | 局域网可明文 | **建议必须**（caddy） | 本机可明文 |
| 数据目录 | `nas/data/` | 自定（env） | 包内 `data/` |
| 常驻 | NAS 常开 | 云主机 24h | 窗口开着才在 |

功能层面四端完全一致：同一套 server + 同一份 WebUI。
