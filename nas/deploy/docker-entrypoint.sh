#!/bin/sh
# 容器入口：以 root 启动 → 修正数据目录属主 → 降权到 node 运行。
#
# 为什么需要：compose 把宿主机目录 bind mount 到 /app/data 时，该目录通常属于
# root（docker 自动创建）或宿主的 1000:1000。若直接以 node 用户启动就会因权限
# 无法写 cookies.enc / synced.json，表现为「登录态保存失败」。
# 这里在启动瞬间把数据目录交给 node，再 exec 降权，容器进程本身仍是非 root。
set -e

DATA_DIR="${PURE_LIVE_DATA_DIR:-/app/data}"

if [ "$(id -u)" = "0" ]; then
    mkdir -p "$DATA_DIR" 2>/dev/null || true
    chown -R node:node "$DATA_DIR" 2>/dev/null || true
    exec su-exec node "$@"
fi

exec "$@"
