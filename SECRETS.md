# Docker Secrets 使用指南

本项目使用Docker Secrets来安全管理敏感信息，如密码等。邮箱地址通过环境变量配置。

## 配置结构

```
infrastructure/
├── docker-compose.yml
├── .env                            # 环境变量配置
├── secrets/
│   ├── postgres_password.txt       # PostgreSQL数据库密码
│   ├── pgadmin_password.txt        # pgAdmin 默认登录密码
│   ├── minio_root_password.txt     # MinIO管理员密码
│   ├── traefik_users.txt          # Traefik管理界面认证用户
│   ├── gitea_db_password.txt      # Gitea数据库密码
│   ├── alicloud_access_key.txt    # 阿里云AccessKey (备份用)
│   ├── alicloud_secret_key.txt    # 阿里云SecretKey (备份用)
│   └── registry_htpasswd.txt      # Docker Registry认证
└── SECRETS.md                      # 本说明文件
```

## 部署前配置

### 1. 创建secrets目录
```bash
mkdir -p secrets
```

### 2. 创建环境变量文件

创建 `.env` 文件配置环境变量:
```bash
# 复制模板文件
cp .env.example .env

# 编辑 .env 文件，填入实际值
cat > .env << EOF
ACME_EMAIL=your-email@example.com              # Let's Encrypt邮箱
BASE_DOMAIN=your-domain.com                    # 你的基础域名
GITEA_RUNNER_TOKEN=your_runner_registration_token  # Gitea Runner注册令牌
EOF
```

### 3. 创建密码文件

**PostgreSQL密码** (建议使用强密码):
```bash
echo "your_secure_postgres_password_123" > secrets/postgres_password.txt
```

**pgAdmin 默认登录密码** (建议使用强密码):
```bash
echo "your_secure_pgadmin_password_123" > secrets/pgadmin_password.txt
```

**MinIO管理员密码** (至少8个字符):
```bash
echo "your_secure_minio_password_123" > secrets/minio_root_password.txt
```

**Gitea数据库密码**:
```bash
echo "your_secure_gitea_db_password_123" > secrets/gitea_db_password.txt
```

**Traefik管理界面认证** (htpasswd格式):
```bash
# 生成用户名和密码的hash (需要htpasswd工具)
htpasswd -nbB admin your_traefik_password > secrets/traefik_users.txt


**Docker Registry认证** (htpasswd格式):
```bash
# 为Registry创建用户认证
docker run --rm httpd:2.4-alpine htpasswd -nbB registry your_registry_password > secrets/registry_htpasswd.txt
```

**阿里云OSS凭证** (用于 `gitea-backup` 服务定时备份 Gitea):

1. 在 OSS 控制台单独新建一个小 bucket 专供备份使用（不要复用 Registry 用的 MinIO），例如 `your-gitea-backup-bucket`，存储类型选**标准存储**，读写权限选**私有**。
2. 在 RAM 访问控制控制台创建一个子账号（不要用主账号 AK/SK），只授予该 bucket 的最小权限，自定义策略示例：
   ```json
   {
     "Version": "1",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "oss:PutObject",
           "oss:GetObject",
           "oss:ListObjects",
           "oss:DeleteObject"
         ],
         "Resource": [
           "acs:oss:*:*:your-gitea-backup-bucket",
           "acs:oss:*:*:your-gitea-backup-bucket/*"
         ]
       }
     ]
   }
   ```
3. 为该子账号创建 AccessKey，写入密钥文件：
   ```bash
   echo "LTAI5t..." > secrets/alicloud_access_key.txt
   echo "your_secret_key" > secrets/alicloud_secret_key.txt
   ```
4. 在该 bucket 上配置生命周期规则，控制云端存储成本上限：控制台 → 该 bucket → 基础设置 → 生命周期 → 新建规则 → 前缀填 `gitea-backups/`（对应 `.env` 中的 `OSS_PREFIX`）→ 启用 → 设置"最后修改时间超过 30 天后删除"。这样即使备份脚本的本地保留逻辑出问题，云端存储也不会无限增长产生费用。
5. 在 `.env` 中设置 `OSS_ENDPOINT`、`OSS_BUCKET`、`OSS_PREFIX`（详见 `.env.example`）。
6. 建议在阿里云费用中心开启消费提醒，作为费用监控的第二道保险。

### 4. 设置文件权限 (推荐)
```bash
chmod 600 secrets/*.txt  # 只有所有者可读写
chmod 700 secrets/       # 只有所有者可访问目录
```

## 服务配置说明

### Traefik配置
- **环境变量**: `ACME_EMAIL` → Let's Encrypt邮箱地址
- **Secret**: `traefik_users` → `/run/secrets/traefik_users`
- **用途**: SSL证书申请邮箱 + 管理界面基本认证
- **认证**: 访问管理界面需要用户名密码

### Portainer配置
- **用户名**: `admin` (固定)
- **密码**: 通过Web界面首次访问时设置
- **用途**: 容器管理界面管理员密码

### PostgreSQL配置
- **Secret**: `postgres_password` → `/run/secrets/postgres_password`
- **环境变量**: `POSTGRES_PASSWORD_FILE`
- **用户**: `postgres` (超级用户)
- **数据库**: `postgres`, `gitea`
- **用途**: 数据库管理员密码

### pgAdmin配置
- **Secret**: `pgadmin_password` → `/run/secrets/pgadmin_password`
- **环境变量**: `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD_FILE`
- **用途**: pgAdmin 管理界面登录账号与密码
- **访问**:
  - 域名: `https://pgadmin.${BASE_DOMAIN}`（通过 Traefik + HTTPS）
  - IP+端口: `http://<服务器IP>:${PGADMIN_PORT}`（默认 `5050`）
  - 首次登录后，在 pgAdmin 中添加服务器：主机 `postgres`，端口 `5432`，用户名 `postgres`，密码为 `secrets/postgres_password.txt` 内容。

### MinIO配置
- **Secret**: `minio_root_password` → `/run/secrets/minio_root_password`
- **环境变量**: `MINIO_ROOT_PASSWORD_FILE`
- **用户名**: `minioadmin` (固定)
- **用途**: 对象存储管理员密码 + Registry S3后端认证

### Gitea配置
- **Secret**: `gitea_db_password` → `/run/secrets/gitea_db_password`
- **环境变量**: `GITEA__database__PASSWD_FILE`
- **数据库用户**: `gitea`
- **数据库名**: `gitea`
- **用途**: Gitea连接PostgreSQL的密码
- **首次访问**: 通过Web界面设置管理员账号

### Gitea Runner配置
- **环境变量**: `GITEA_RUNNER_TOKEN` (从.env读取)
- **用途**: Runner注册到Gitea实例的令牌
- **获取方式**: Gitea管理后台 → 站点管理 → Actions → Runners → 创建Runner令牌

### Docker Registry配置
- **Secret**: `registry_htpasswd` → `/auth/htpasswd`
- **Secret**: `minio_root_password` (S3后端认证)
- **用户名**: 在htpasswd文件中定义 (推荐使用`registry`)
- **用途**: 镜像推送/拉取认证 + MinIO存储后端

### 阿里云OSS配置 (gitea-backup 服务使用)
- **Secret**: `alicloud_access_key` → `/run/secrets/alicloud_access_key`
- **Secret**: `alicloud_secret_key` → `/run/secrets/alicloud_secret_key`
- **Secret**: `gitea_db_password`（复用，用于 `pg_dump` 导出 `gitea` 数据库）
- **用途**: `gitea-backup` 服务按 `BACKUP_CRON_SCHEDULE` 定时把 Gitea 仓库数据 + 数据库 dump 打包上传到 OSS
- **注意**: 未配置这两个 secret 文件时 `gitea-backup` 容器会启动失败（`entrypoint.sh` 会因读取不到密钥文件而报错），如暂不需要自动备份，可以直接在 `docker-compose.yml` 中注释掉该服务

## 部署命令

```bash
# 1. 创建secrets目录和所有必需的secret文件
mkdir -p secrets

# 2. 创建环境变量文件
cat > .env << EOF
ACME_EMAIL=your-email@example.com
GITEA_RUNNER_TOKEN=your_runner_token
EOF

# 3. 创建所有secret文件（按上述说明填写）
echo "your_postgres_password" > secrets/postgres_password.txt
echo "your_minio_password" > secrets/minio_root_password.txt
echo "your_gitea_db_password" > secrets/gitea_db_password.txt
docker run --rm httpd:2.4-alpine htpasswd -nbB admin your_traefik_password > secrets/traefik_users.txt
docker run --rm httpd:2.4-alpine htpasswd -nbB registry your_registry_password > secrets/registry_htpasswd.txt

# 4. 设置文件权限
chmod 600 secrets/*.txt
chmod 700 secrets/

# 5. 创建外部网络
docker network create traefik

# 6. 初始化PostgreSQL数据库（首次部署需要先启动postgres）
docker-compose up -d postgres
sleep 10
docker exec -it postgres psql -U postgres -c "CREATE DATABASE gitea;"
docker exec -it postgres psql -U postgres -c "CREATE USER gitea WITH PASSWORD '$(cat secrets/gitea_db_password.txt)';"
docker exec -it postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE gitea TO gitea;"

# 7. 创建MinIO存储桶（首次部署）
docker-compose up -d minio
sleep 10
docker exec -it minio mc alias set local http://localhost:9000 minioadmin $(cat secrets/minio_root_password.txt)
docker exec -it minio mc mb local/docker-registry

# 8. 启动所有服务
docker-compose up -d

# 9. 检查服务状态
docker-compose ps

# 10. 查看日志
docker-compose logs -f
```

## 访问应用时的认证信息

### Traefik管理界面
- **URL**: https://traefik.your-domain.com
- **用户名**: `admin` (在traefik_users.txt中配置的)
- **密码**: 创建traefik_users.txt时设置的密码

### Portainer管理界面
- **URL**: https://portainer.your-domain.com
- **用户名**: `admin`
- **密码**: 首次访问时在Web界面设置的密码

### Gitea Web界面
- **URL**: https://git.your-domain.com
- **用户名**: 首次访问时创建的管理员账号
- **密码**: 首次设置的密码
- **SSH访问**: `git@git.your-domain.com:2222`

### MinIO管理控制台
- **URL**: https://minio-console.your-domain.com
- **用户名**: `minioadmin`
- **密码**: `secrets/minio_root_password.txt`的内容

### Docker Registry
- **URL**: https://registry.your-domain.com
- **用户名**: `registry` (在registry_htpasswd.txt中配置的)
- **密码**: 创建registry_htpasswd.txt时设置的密码
- **登录命令**: `docker login registry.your-domain.com`
