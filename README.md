# 基础设施服务栈

基于 Docker Compose 的自托管开发基础设施，提供完整的代码托管、CI/CD、对象存储和容器管理能力。

## 服务列表

### 核心服务

| 服务 | 版本 | 说明 | 访问地址 |
|-----|------|------|---------|
| **Traefik** | v3.1 | 反向代理 + 自动SSL证书管理 | `https://traefik.${BASE_DOMAIN}` |
| **Portainer** | latest | Docker容器可视化管理 | `https://portainer.${BASE_DOMAIN}` |
| **PostgreSQL** | 16-alpine | 关系型数据库 | `localhost:5432` |
| **MinIO** | latest | S3兼容对象存储 | `https://minio.${BASE_DOMAIN}` |
| **Gitea** | 1.21 | 自托管Git服务 + Actions | `https://git.${BASE_DOMAIN}` |
| **Gitea Runner** | latest | CI/CD任务执行器 | 内部服务 |
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

## 数据持久化

所有重要数据存储在Docker Volumes中：

- `postgres_data` - 数据库文件
- `gitea_data` - Git仓库和配置
- `minio_data` - 对象存储数据
- `traefik_acme` - SSL证书
- `portainer_data` - Portainer配置
- `gitea_runner_data` - Runner缓存

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

## 备份建议

定期备份以下数据：
- PostgreSQL数据库（使用pg_dump）
- Gitea数据目录
- MinIO对象存储
- `.env` 和 `secrets/` 目录

## 许可证

MIT License
