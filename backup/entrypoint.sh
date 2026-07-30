#!/bin/bash
set -euo pipefail

RCLONE_CONFIG_DIR="/root/.config/rclone"
mkdir -p "$RCLONE_CONFIG_DIR"

ACCESS_KEY=$(cat /run/secrets/alicloud_access_key)
SECRET_KEY=$(cat /run/secrets/alicloud_secret_key)

cat > "${RCLONE_CONFIG_DIR}/rclone.conf" <<EOF
[oss]
type = s3
provider = Alibaba
access_key_id = ${ACCESS_KEY}
secret_access_key = ${SECRET_KEY}
endpoint = ${OSS_ENDPOINT}
acl = private
EOF
chmod 600 "${RCLONE_CONFIG_DIR}/rclone.conf"

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

CRON_SCHEDULE="${BACKUP_CRON_SCHEDULE:-0 3 * * *}"
echo "${CRON_SCHEDULE} /usr/local/bin/backup.sh >> /proc/1/fd/1 2>> /proc/1/fd/2" > /etc/crontabs/root

echo "gitea-backup: 定时计划已设置为「${CRON_SCHEDULE}」，目标 oss:${OSS_BUCKET}/${OSS_PREFIX}"

exec crond -f -l 2
