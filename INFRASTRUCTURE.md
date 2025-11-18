# 基础设施服务部署

## 核心服务

### 1. Traefik (反向代理 + SSL)
- **功能**：反向代理 + 自动SSL证书管理
- **端口**：
  - 80 (HTTP)
  - 443 (HTTPS)
  - 8080 (管理界面)
- **配置**：
  - 自动发现Docker容器
  - Let's Encrypt自动证书申请
  - HTTP自动重定向到HTTPS
  - 基本认证保护管理界面

### 2. Portainer (容器管理)
- **功能**：Docker容器可视化管理
- **访问**：Web界面管理所有容器
- **用途**：部署、监控、日志查看、Webhook触发部署

### 3. PostgreSQL (关系型数据库)
- **版本**：16-alpine
- **端口**：5432
- **数据库**：
  - `postgres` - 默认数据库
  - `gitea` - Gitea专用数据库
- **用途**：项目数据存储、Gitea后端存储
- **健康检查**：每10秒检查一次

### 4. MinIO (对象存储)
- **功能**：S3兼容对象存储
- **端口**：
  - 9000 (S3 API)
  - 9001 (管理控制台)
- **存储桶**：
  - `docker-registry` - Docker镜像仓库存储
- **用途**：文件存储、Docker Registry后端

### 5. Gitea (Git仓库服务)
- **版本**：1.21
- **端口**：
  - 3000 (Web界面)
  - 2222 (SSH访问)
- **功能**：
  - Git仓库托管
  - Gitea Actions (CI/CD)
  - 代码审查、Issues、Wiki
- **配置**：
  - 使用PostgreSQL存储数据
  - 禁用公开注册
  - 需要登录才能查看

### 6. Gitea Runner (CI/CD执行器)
- **功能**：执行Gitea Actions工作流
- **标签**：
  - `ubuntu-latest`
  - `ubuntu-22.04`
  - `ubuntu-24.04`
- **配置**：
  - 全局范围runner
  - 使用Docker执行任务
  - 访问宿主机Docker socket

### 7. Docker Registry (私有镜像仓库)
- **版本**：2.8
- **端口**：5000
- **存储**：MinIO S3后端
- **认证**：htpasswd基本认证
- **功能**：
  - 推送/拉取Docker镜像
  - 支持删除镜像
  - CORS跨域支持

## 网络架构

### 外部网络
- **traefik**：所有需要外部访问的服务

### 内部网络
- **internal**：服务间内部通信（PostgreSQL、MinIO、Gitea等）

## 数据持久化

### Docker Volumes
- `traefik_acme` - SSL证书存储
- `portainer_data` - Portainer配置
- `postgres_data` - 数据库文件
- `minio_data` - 对象存储数据
- `gitea_data` - Git仓库和配置
- `gitea_runner_data` - Runner数据
- `backup_data` - 备份文件

## 部署顺序

1. **准备环境**
   ```bash
   # 创建外部网络
   docker network create traefik

   # 准备secrets文件（见SECRETS.md）
   mkdir -p secrets
   ```

2. **配置环境变量**
   ```bash
   # 复制环境变量模板
   cp .env.example .env

   # 编辑 .env 文件，填入你的实际配置
   # ACME_EMAIL=your-email@example.com
   # BASE_DOMAIN=your-domain.com
   # GITEA_RUNNER_TOKEN=your_runner_token
   ```

3. **启动服务**
   ```bash
   # 启动所有服务
   docker-compose up -d

   # 检查服务状态
   docker-compose ps
   ```

4. **初始化Gitea数据库**
   ```bash
   docker exec -it postgres psql -U postgres -c "CREATE DATABASE gitea;"
   docker exec -it postgres psql -U postgres -c "CREATE USER gitea WITH PASSWORD 'your_gitea_db_password';"
   docker exec -it postgres psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE gitea TO gitea;"
   ```

5. **注册Gitea Runner**
   ```bash
   # 首次启动后需要手动注册
   docker exec -it gitea-runner act_runner register
   ```

## 域名配置

| 服务 | 域名模式 | 说明 |
|-----|---------|------|
| Traefik | `traefik.${BASE_DOMAIN}` | 反向代理管理界面 |
| Portainer | `portainer.${BASE_DOMAIN}` | 容器管理界面 |
| MinIO API | `minio.${BASE_DOMAIN}` | S3 API端点 |
| MinIO Console | `minio-console.${BASE_DOMAIN}` | MinIO管理控制台 |
| Gitea | `git.${BASE_DOMAIN}` | Git仓库Web界面 |
| Registry | `registry.${BASE_DOMAIN}` | Docker镜像仓库 |

**说明**: 域名通过 `.env` 文件中的 `BASE_DOMAIN` 变量配置。例如设置 `BASE_DOMAIN=example.com`，则 Traefik 域名为 `traefik.example.com`。

## 服务依赖关系

```
Traefik (反向代理层)
  ├─ Portainer
  ├─ MinIO
  ├─ Gitea → PostgreSQL
  └─ Registry → MinIO

PostgreSQL (数据层)
  └─ Gitea → Gitea Runner

MinIO (存储层)
  └─ Registry
```

## 访问地址汇总

### 管理界面
- **Traefik**: https://traefik.your-domain.com (需认证)
- **Portainer**: https://portainer.your-domain.com
- **MinIO Console**: https://minio-console.your-domain.com
- **Gitea**: https://git.your-domain.com

### API端点
- **MinIO S3 API**: https://minio.your-domain.com
- **Docker Registry**: https://registry.your-domain.com
- **PostgreSQL**: `服务器IP:5432`

### SSH访问
- **Gitea SSH**: `git.your-domain.com:2222`

**注意**: 将 `your-domain.com` 替换为你在 `.env` 中配置的 `BASE_DOMAIN` 实际值。

## 健康检查

所有服务配置了健康检查机制：
- **PostgreSQL**: 每10秒检查 `pg_isready`
- **MinIO**: 每30秒检查健康端点
- **Gitea**: 每10秒检查HTTP可用性
- **Registry**: 已禁用（通过entrypoint启动）
