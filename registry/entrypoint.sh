#!/bin/sh

# 读取MinIO密码
MINIO_PASSWORD=$(cat /run/secrets/minio_root_password)

# 替换配置文件中的密码占位符
sed "s/__SECRET_KEY__/$MINIO_PASSWORD/g" /etc/docker/registry/config.yml > /tmp/config.yml

# 启动registry
exec registry serve /tmp/config.yml