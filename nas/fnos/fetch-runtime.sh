#!/usr/bin/env bash
# 下载 FPK 打包所需的 Linux x64 Node 运行时(已 gitignore, 打包前执行一次):
#   node -> purelive/app/runtime/node
# 走 npmmirror 国内镜像; 版本与 nas/server 的 engines(>=20) 及开发机一致。
set -euo pipefail
cd "$(dirname "$0")"

NODE_VER="v20.18.1"
OUT="purelive/app/runtime/node"

if [ -s "$OUT" ]; then
    echo "node 已存在, 跳过: $OUT"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "下载 node ${NODE_VER} (linux x64) ..."
curl -sL --max-time 600 -o "$tmp/node.tar.gz" \
    "https://npmmirror.com/mirrors/node/${NODE_VER}/node-${NODE_VER}-linux-x64.tar.gz"
tar xzf "$tmp/node.tar.gz" -C "$tmp"
cp "$tmp/node-${NODE_VER}-linux-x64/bin/node" "$OUT"
chmod +x "$OUT"
echo "  -> $OUT"
