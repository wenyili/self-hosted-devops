# 基础设施服务栈

基于 Docker Compose 的自托管开发基础设施，提供完整的代码托管、CI/CD、对象存储和容器管理能力。

## 服务列表

### 核心服务

| 服务 | 版本 | 说明 | 访问地址 |
|-----|------|------|---------|
| **Traefik** | v3.1 | 反向代理 + 自动SSL证书管理 | `https://traefik.${BASE_DOMAIN}` |
| **Portainer** | latest | Docker容器可视化管理 | `https://portainer.${BASE_DOMAIN}` |
| **PostgreSQL** | 16-alpine | 关系型数据库 | `localhost:${POSTGRES_PORT}`（默认 `5432`） |
| **pgAdmin** | latest | PostgreSQL 可视化管理 | `https://pgadmin.${BASE_DOMAIN}` 或 `http://<IP>:${PGADMIN_PORT}` |
| **MinIO** | latest | S3兼容对象存储 | `https://minio.${BASE_DOMAIN}` |
| **Gitea** | 1.21 | 自托管Git服务 + Actions | `https://git.${BASE_DOMAIN}` 或 `http://<IP>:${GITEA_HTTP_PORT}`（SSH: `<IP>:${GITEA_SSH_PORT}`） |
| **Gitea Runner** | latest | CI/CD任务执行器 | 内部服务 |
| **Gitea Backup** | 自建 | 定时备份Gitea数据到阿里云OSS | 内部服务 |
| **Docker Registry** | 2.8 | 私有Docker镜像仓库 | `https://registry.${BASE_DOMAIN}` |

### 功能特性

- ✅ **自动HTTPS**: Let's Encrypt自动申请和续期SSL证书
- ✅ **代码托管**: 完整的Git仓库托管，支持SSH和HTTPS
- ✅ **CI/CD**: Gitea Actions工作流，类似GitHub Actions
- ✅ **镜像管理**: 私有Docker镜像仓库，使用MinIO作为存储后端
- ✅ **对象存储**: S3兼容API，可存储文件和静态资源
- ✅ **容器管理**: Web界面管理所有Docker容器
- ✅ **数据持久化**: 所有数据通过Docker Volumes持久化存储

## 快速开始

### 前置要求

- Docker 20.10+
- Docker Compose 2.0+
- 一个域名并配置好DNS解析

### 部署步骤

1. **配置环境变量**
   ```bash
   cp .env.example .env
   # 编辑 .env 文件，设置你的域名和邮箱
   ```

2. **创建密钥文件**
   ```bash
   # 详见 SECRETS.md
   mkdir -p secrets
   ```

3. **创建Docker网络**
   ```bash
   docker network create traefik
   ```

4. **启动服务**
   ```bash
   docker-compose up -d
   ```

5. **查看状态**
   ```bash
   docker-compose ps
   ```

## 文档

- [INFRASTRUCTURE.md](INFRASTRUCTURE.md) - 详细的服务架构和配置说明
- [SECRETS.md](SECRETS.md) - 密钥和密码管理指南

## 架构图

```
Internet
   ↓
Traefik (反向代理 + SSL)
   ├─→ Portainer (容器管理)
   ├─→ Gitea (Git仓库) → PostgreSQL (数据库)
   ├─→ MinIO (对象存储)
   └─→ Registry (镜像仓库) → MinIO (存储后端)

内部网络:
   ├─ Gitea Runner (CI/CD执行器)
   ├─ Gitea Backup (定时备份 → 阿里云OSS)
   └─ PostgreSQL (数据库)
```

## 域名配置

所有服务使用子域名访问，通过 `.env` 中的 `BASE_DOMAIN` 配置：

- `traefik.${BASE_DOMAIN}` - Traefik管理面板
- `portainer.${BASE_DOMAIN}` - 容器管理界面
- `git.${BASE_DOMAIN}` - Gitea Web界面
- `minio.${BASE_DOMAIN}` - MinIO API端点
- `minio-console.${BASE_DOMAIN}` - MinIO管理控制台
- `registry.${BASE_DOMAIN}` - Docker镜像仓库
- `pgadmin.${BASE_DOMAIN}` - pgAdmin 数据库管理界面（IP访问：`http://<IP>:${PGADMIN_PORT}`）
  
IP+端口直连（域名不可用时）：
- PostgreSQL: `http://<IP>:${POSTGRES_PORT}`（默认 `5432`）
- Gitea Web: `http://<IP>:${GITEA_HTTP_PORT}`（默认 `3000`）
- Gitea SSH: `<IP>:${GITEA_SSH_PORT}`（默认 `2222`）

## 数据持久化

所有重要数据存储在Docker Volumes中：

- `postgres_data` - 数据库文件
- `pgadmin_data` - pgAdmin 配置/会话数据
- `gitea_data` - Git仓库和配置
- `minio_data` - 对象存储数据
- `traefik_acme` - SSL证书
- `portainer_data` - Portainer配置
- `gitea_runner_data` - Runner缓存
- `backup_data` - `gitea-backup` 服务的本地备份归档（滚动保留最近 N 份，同时上传一份到阿里云OSS）

## 常用命令

```bash
# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f [service_name]

# 重启服务
docker-compose restart [service_name]

# 停止所有服务
docker-compose down

# 更新服务
docker-compose pull
docker-compose up -d
```

## 安全说明

- 所有密码通过Docker Secrets管理，不在配置文件中硬编码
- SSL证书自动续期
- Traefik管理界面使用HTTP基本认证保护
- Gitea禁用公开注册，需要登录才能查看
- Docker Registry使用htpasswd认证

## 备份

`gitea-backup` 服务会按 `.env` 中的 `BACKUP_CRON_SCHEDULE`（默认每天 03:00）自动执行：

1. `pg_dump` 导出 PostgreSQL 中的 `gitea` 数据库
2. 打包 `gitea_data` 卷（仓库文件、`app.ini`、attachments 等）
3. 合并为单个归档写入本地 `backup_data` 卷（默认保留最近 `BACKUP_LOCAL_KEEP` 份，超出自动删除）
4. 上传到阿里云 OSS（`OSS_BUCKET`/`OSS_PREFIX`），云端过期依赖 bucket 的生命周期规则（见 [SECRETS.md](SECRETS.md)）

配置步骤（RAM子账号、bucket、生命周期规则）见 [SECRETS.md](SECRETS.md) 中"阿里云OSS配置"一节。

**手动立即触发一次备份**（用于验证配置是否正确）：
```bash
docker compose run --rm gitea-backup /usr/local/bin/backup.sh
docker compose logs -f gitea-backup
```

**其它需要手动保管的数据**：`.env` 和 `secrets/` 目录（含所有密码和 OSS 密钥），以及 MinIO 对象存储（如有需要，自行定期同步）。

### 从 OSS 恢复备份

恢复是破坏性操作（会覆盖现有数据），需要人工确认后手动执行，没有自动化脚本：

1. 从 OSS 下载指定日期的备份：
   ```bash
   docker compose run --rm gitea-backup rclone copy oss:${OSS_BUCKET}/${OSS_PREFIX}/gitea_backup_<时间戳>.tar /backup/
   ```
2. 解压得到数据库 dump 和仓库数据：
   ```bash
   docker compose exec gitea-backup tar xf /backup/gitea_backup_<时间戳>.tar -C /backup/restore
   ```
3. 停止 `gitea` 容器：`docker compose stop gitea`
4. 恢复数据库：清空/重建 `gitea` 库后，用 `psql` 导入解压出的 `gitea_db.sql.gz`
5. 清空 `gitea_data` 卷内容，解压 `gitea_data.tar.gz` 到位
6. 重启 `gitea` 容器并验证：`docker compose start gitea`

## 许可证

MIT License
