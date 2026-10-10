#!/usr/bin/env bash
# 重建 authelia 容器使 configuration.yml / compose 的改动生效，并等它健康。
# Authelia 启动时会把挂载的 ./authelia 目录改成 root 所有，这会让之后的 git pull 失败，所以重建后把所有者还给当前用户。
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose up -d --no-deps --force-recreate authelia
sudo chown -R "$(id -u):$(id -g)" authelia
for _ in $(seq 1 45); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' authelia)" = healthy ] && { echo "authelia 已健康"; exit 0; }
  sleep 2
done
echo "authelia 重建后不健康" >&2; docker logs --tail 20 authelia >&2; exit 1
