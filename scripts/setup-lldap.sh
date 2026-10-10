#!/usr/bin/env bash
# lldap 一次性初始化（在服务器的 ~/self-hosted-devops 里以 ubuntu 运行，可重复运行）：
#   1) 生成 secrets/ 下的 4 个密钥文件（lldap JWT、key seed、管理员密码、Authelia 的绑定账号密码）
#   2) 在现有 Postgres 里创建 lldap 库和角色，并把连接串、Base DN 写进 .env
# 所有密钥只写入文件，不会打印。管理员密码请自己在终端查看：  cat secrets/lldap_admin_password.txt
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077

alnum() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
mk() { [ -s "secrets/$1.txt" ] && echo "  已存在 secrets/$1.txt，跳过" || { printf '%s' "$2" > "secrets/$1.txt"; echo "  已生成 secrets/$1.txt"; }; }

echo "==> 1/2 密钥文件"
mkdir -p secrets
mk lldap_jwt_secret "$(openssl rand -hex 32)"
mk lldap_key_seed "$(openssl rand -hex 32)"
mk lldap_admin_password "$(alnum 24)"
mk authelia_ldap_password "$(alnum 24)"

echo "==> 2/2 Postgres 库与 .env"
[ -f .env ] || { echo ".env 不存在" >&2; exit 1; }
[ -n "$(tail -c1 .env)" ] && echo >> .env       # 保证以换行结尾
BASE_DOMAIN=$(grep '^BASE_DOMAIN=' .env | cut -d= -f2-)
[ -n "$BASE_DOMAIN" ] || { echo ".env 里没有 BASE_DOMAIN" >&2; exit 1; }
if grep -q '^LLDAP_BASE_DN=' .env; then echo "  .env 已有 LLDAP_BASE_DN"; else
  echo "LLDAP_BASE_DN=dc=${BASE_DOMAIN//./,dc=}" >> .env; echo "  已写入 LLDAP_BASE_DN"; fi
if grep -q '^LLDAP_DATABASE_URL=' .env; then echo "  .env 已有 LLDAP_DATABASE_URL，跳过建库"; else
  DBPW=$(alnum 24)
  docker exec -i postgres psql -U postgres -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$ BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'lldap') THEN ALTER ROLE lldap LOGIN PASSWORD '$DBPW';
  ELSE CREATE ROLE lldap LOGIN PASSWORD '$DBPW'; END IF;
END \$\$;
SELECT 'CREATE DATABASE lldap OWNER lldap' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lldap')\gexec
SQL
  echo "LLDAP_DATABASE_URL=postgres://lldap:${DBPW}@postgres/lldap" >> .env
  unset DBPW; echo "  已创建 lldap 库/角色，并写入 LLDAP_DATABASE_URL"
fi
echo "完成。下一步： docker compose up -d lldap"
