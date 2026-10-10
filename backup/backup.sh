#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WORKDIR="/backup/tmp_${TIMESTAMP}"
ARCHIVE_NAME="gitea_backup_${TIMESTAMP}.tar"
FINAL_PATH="/backup/${ARCHIVE_NAME}"

PG_HOST="${PG_HOST:-postgres}"
PG_PORT="${PG_PORT:-5432}"
PG_DATABASE="${PG_DATABASE:-gitea}"
PG_USER="${PG_USER:-gitea}"

OSS_BUCKET="${OSS_BUCKET:?OSS_BUCKET 未设置}"
OSS_PREFIX="${OSS_PREFIX:-gitea-backups}"
BACKUP_LOCAL_KEEP="${BACKUP_LOCAL_KEEP:-7}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

log "开始备份: ${TIMESTAMP}"
mkdir -p "$WORKDIR"

log "导出 PostgreSQL 数据库 ${PG_DATABASE}..."
PGPASSWORD=$(cat /run/secrets/gitea_db_password) \
  pg_dump -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
  | gzip > "${WORKDIR}/gitea_db.sql.gz"

# 其它数据库：以超级用户逐个导出（排除 gitea 本身——上面已导出——和 postgres 系统库）。
EXTRA_DBS=""
if [ "${BACKUP_ALL_DATABASES:-0}" = "1" ]; then
  export PGPASSWORD="$(cat /run/secrets/postgres_password)"
  for db in $(psql -h "$PG_HOST" -p "$PG_PORT" -U postgres -d postgres -Atc \
      "select datname from pg_database where not datistemplate and datname not in ('postgres','${PG_DATABASE}') order by 1"); do
    log "导出 PostgreSQL 数据库 ${db}..."
    pg_dump -h "$PG_HOST" -p "$PG_PORT" -U postgres -d "$db" | gzip > "${WORKDIR}/db_${db}.sql.gz"
    EXTRA_DBS="${EXTRA_DBS} db_${db}.sql.gz"
  done
  unset PGPASSWORD
fi

log "打包 gitea_data 卷..."
tar czf "${WORKDIR}/gitea_data.tar.gz" -C /source/gitea_data --exclude='log' .

log "生成最终归档 ${ARCHIVE_NAME}（内部两个成员已各自压缩，外层不再重复压缩）..."
tar cf "$FINAL_PATH" -C "$WORKDIR" gitea_db.sql.gz gitea_data.tar.gz $EXTRA_DBS

SIZE=$(du -h "$FINAL_PATH" | cut -f1)
log "本地归档完成: ${FINAL_PATH} (${SIZE})"

log "上传到 oss:${OSS_BUCKET}/${OSS_PREFIX}/ ..."
rclone copy "$FINAL_PATH" "oss:${OSS_BUCKET}/${OSS_PREFIX}/" --s3-no-check-bucket
log "上传完成"

log "清理本地旧备份，只保留最近 ${BACKUP_LOCAL_KEEP} 份..."
ls -1t /backup/gitea_backup_*.tar 2>/dev/null | tail -n +$((BACKUP_LOCAL_KEEP + 1)) | xargs -r rm -f

log "备份流程结束: ${TIMESTAMP}"
