#!/usr/bin/env bash
# 组装 Pure Live 电脑便携包（无 NAS 的 Windows 电脑直跑 Web 端）。
#
# 前置（产物已就绪）：
#   cd nas/server && npm run build     # tsc 编译（含 PURE_LIVE_WEBUI_DIR 静态托管）
#   cd nas/webui  && npm run build     # vite 构建
#   node.exe 就绪（默认取 E:/codex/tools/node/node-v20.18.1-win-x64/node.exe，
#   可用 PORTABLE_NODE env 覆盖）
#
# 产出：E:/codex/purelive-portable/pure_live_portable/
#   node/node.exe  server/{dist,node_modules(仅生产依赖)}  webui/  data/  启动.bat  使用说明.txt
# 启动.bat / 使用说明.txt 由本脚本生成，避免编码问题。
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${PORTABLE_OUT:-/e/codex/purelive-portable/pure_live_portable}"
NODE_EXE="${PORTABLE_NODE:-/e/codex/tools/node/node-v20.18.1-win-x64/node.exe}"
PORT="${PORT:-8090}"

[ -f "$NODE_EXE" ] || { echo "node.exe not found: $NODE_EXE"; exit 1; }
[ -d "$REPO/nas/server/dist" ] || { echo "server dist missing, run npm run build in nas/server"; exit 1; }
[ -d "$REPO/nas/webui/dist" ] || { echo "webui dist missing, run npm run build in nas/webui"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/node" "$OUT/server" "$OUT/webui" "$OUT/data"
cp "$NODE_EXE" "$OUT/node/"
cp -r "$REPO/nas/server/dist" "$OUT/server/"
cp -r "$REPO/nas/server/node_modules" "$OUT/server/"
cp -r "$REPO/nas/webui/dist/." "$OUT/webui/"

# 只留生产依赖（去掉 tsx/typescript 等 dev 依赖，54MB -> 约 20MB）
if [ -d "$REPO/nas/server" ]; then
  (cd "$OUT/server" && PATH="/e/codex/tools/node/node-v20.18.1-win-x64:$PATH" \
    npm prune --omit=dev >/dev/null 2>&1 || echo "warn: npm prune failed (package larger than needed)")
fi

# 启动脚本（ASCII only，避免 bat 中文乱码）
cat > "$OUT/启动.bat" <<BAT
@echo off
rem Pure Live portable launcher (ASCII only to avoid codepage issues)
cd /d "%~dp0"
set "PURE_LIVE_DATA_DIR=%~dp0data"
set "PURE_LIVE_WEBUI_DIR=%~dp0webui"
set "PORT=$PORT"
if not exist "%PURE_LIVE_DATA_DIR%" mkdir "%PURE_LIVE_DATA_DIR%"
echo ============================================
echo  Pure Live Web (portable)  http://localhost:$PORT
echo  Data folder: %PURE_LIVE_DATA_DIR%
echo  Close this window to stop the server.
echo ============================================
start "" cmd /c "timeout /t 2 >nul & start http://localhost:$PORT"
"node\\node.exe" "server\\dist\\index.js"
pause
BAT

cat > "$OUT/使用说明.txt" <<TXT
Pure Live 电脑便携版使用说明
================================

这是什么：
一个不需要 NAS 的电脑版 Pure Live 服务。解压即用，双击「启动.bat」，
浏览器自动打开 http://localhost:$PORT ，功能和 NAS 版 Web 端完全一致
（五平台观看、弹幕、关注同步、屏蔽、测速等）。

使用步骤：
1. 把整个文件夹解压到任意位置（路径建议不要包含特殊字符）。
2. 双击「启动.bat」，约 2 秒后浏览器自动打开 http://localhost:$PORT 。
   如果浏览器没有自动打开，手动在浏览器地址栏输入 http://localhost:$PORT 。
3. 关闭黑色命令行窗口 = 停止服务。

让手机 App 也连上它（可选）：
1. 确保手机和电脑在同一个局域网（同一 WiFi）。
2. 查看电脑的局域网 IP（Win+R 输入 cmd，运行 ipconfig，看 IPv4 地址）。
3. App 里「设置 → 备份与恢复 → NAS 服务器同步」地址填
   http://<电脑局域网IP>:$PORT ，关注列表即可与电脑双向同步。

常见问题：
- 端口被占用：用记事本编辑「启动.bat」，把 $PORT 改成其他端口。
- 浏览器打开是空白：确认没有关闭黑色命令行窗口（窗口关了服务就停了）。
- 想开机自启：把「启动.bat」的快捷方式放到 shell:startup 文件夹。
- 数据保存在文件夹内的 data 目录，删除整个文件夹即完全卸载。
TXT

echo "portable package ready: $OUT"
du -sh "$OUT"/* | sed "s|$OUT/||"
