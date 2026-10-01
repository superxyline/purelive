#!/usr/bin/env bash
# 组装并打包 Pure Live 飞牛 FPK。
#
# 流程:
#   1. (缺产物时) 构建 server(tsc) 与 webui(vite)
#   2. 组装 purelive/app/{server,webui}  <- 仓库构建产物(始终以仓库为准)
#   3. (缺运行时) 下载 Linux node 进 purelive/app/runtime
#   4. fnpack build 打包 (必须在 purelive/ 目录内跑, .fpk 落在 cwd)
#   5. repack: 把 app/ui 复制到 fpk 外层顶层 ui/ —— 移动端应用中心不解
#      app.tgz, 不 repack 手机上图标是灰占位
#
# 产出: nas/fnos/purelive.fpk
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FNOS_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${FNOS_DIR}/purelive/app"
FNPACK="${FNPACK:-/e/codex/tools/fnos/fnpack.exe}"
NODE_EXE="${PORTABLE_NODE:-/e/codex/tools/node/node-v20.18.1-win-x64/node.exe}"
export PATH="$(dirname "$NODE_EXE"):$PATH"

[ -x "$(command -v node)" ] || { echo "node.exe not found: $NODE_EXE"; exit 1; }
[ -f "$FNPACK" ] || { echo "fnpack not found: $FNPACK"; exit 1; }

# ---- 1. 构建(缺才建) ----------------------------------------------------
if [ ! -f "$REPO/nas/server/dist/index.js" ]; then
    echo "building server (tsc) ..."
    (cd "$REPO/nas/server" && npm run build >/dev/null)
fi
if [ ! -f "$REPO/nas/webui/dist/index.html" ]; then
    echo "building webui (vite) ..."
    (cd "$REPO/nas/webui" && npm run build >/dev/null)
fi

# ---- 2. 组装 app/server 与 app/webui -----------------------------------
echo "assembling app/server + app/webui ..."
rm -rf "$APP_DIR/server" "$APP_DIR/webui"
mkdir -p "$APP_DIR/server" "$APP_DIR/webui"
cp -r "$REPO/nas/server/dist" "$APP_DIR/server/dist"
cp -r "$REPO/nas/server/node_modules" "$APP_DIR/server/node_modules"
cp -r "$REPO/nas/webui/dist/." "$APP_DIR/webui/"
(cd "$APP_DIR/server" && npm prune --omit=dev >/dev/null 2>&1) \
    || echo "warn: npm prune failed (包会比需要的大)"

# ---- 3. Node 运行时 ------------------------------------------------------
if [ ! -s "$APP_DIR/runtime/node" ]; then
    bash "${FNOS_DIR}/fetch-runtime.sh"
fi

# ---- 4. 打包 ------------------------------------------------------------
# Git Bash 下 chmod 决定 tar 记录的 exec 位: 脚本与 node 必须可执行
chmod +x "${FNOS_DIR}/purelive/cmd/"* "${APP_DIR}/runtime/node"
cd "${FNOS_DIR}/purelive"
rm -f purelive.fpk
"$FNPACK" build   # 坑: .fpk 落在 cwd, 不在 --directory 指定处

# ---- 5. repack 移动端图标 ------------------------------------------------
FPK="${FNOS_DIR}/purelive/purelive.fpk"
REPACK="$(mktemp -d)"
trap 'rm -rf "${REPACK}"' EXIT
tar -xzf "$FPK" -C "$REPACK"
cp -r "$APP_DIR/ui" "$REPACK/ui"
tar -C "$REPACK" -czf "$FPK" .
mv "$FPK" "${FNOS_DIR}/purelive.fpk"

echo "fpk ready: ${FNOS_DIR}/purelive.fpk"
tar -tzf "${FNOS_DIR}/purelive.fpk" | grep -v '^app.tgz$' | grep -v '^\./$' | sort
du -sh "${FNOS_DIR}/purelive.fpk"
