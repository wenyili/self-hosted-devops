# 基础设施服务部署

## 核心服务

### 1. Traefik (反向代理 + SSL)
- **功能**：反向代理 + 自动SSL证书管理
- **端口**：
  - 80 (HTTP)
  - 443 (HTTPS)
- **配置**：
  - 自动发现Docker容器
  - Let's Encrypt自动证书申请
  - HTTP自动重定向到HTTPS
  - 管理控制台仅通过 `traefik.${BASE_DOMAIN}` 访问，由 Authelia 保护（已关闭 8080 端口和 insecure API）

### 2. PostgreSQL (关系型数据库)
- **版本**：16-alpine
- **端口**：
  - 内部: 5432
  - Docker 内网 `postgres:5432`；宿主机仅绑定 `127.0.0.1:5432`（外网不可达）
  - 本机访问：`ssh -N -L 5432:localhost:5432 tencent_liwenyi`，然后连 `localhost:5432`
- **数据库**：
  - `postgres` - 默认数据库
  - `gitea` - Gitea专用数据库
- **用途**：项目数据存储、Gitea后端存储
- **健康检查**：每10秒检查一次

### 3. Authelia (统一登录 / SSO)
- **功能**：为 `myapps.${BASE_DOMAIN}` 下的应用提供一次登录、全站通用的会话（cookie 域 `.${BASE_DOMAIN}`，默认 30 天，"记住我" 1 年）
- **访问**：`auth.${BASE_DOMAIN}`
- **接入方式**：应用 router 的 middlewares 里写 `authelia@docker`（放在 redirect/stripprefix 之前），不再使用 BasicAuth
- **用户**：`authelia/users_database.yml`（不进 git，模板见 `.example`，root 所有需 sudo）；hash 用
  `docker run --rm -it authelia/authelia:4.39 authelia crypto hash generate argon2` 生成，改文件后 `docker restart authelia`
- **访问规则**：`authelia/local.yml`（域名与用户名，**不入库**，示例见 `local.yml.example`）里的 `access_control`，新增受保护域名要在这里加规则（默认 deny）；`configuration.yml` 只放通用配置，两者合并加载
- **改完配置**：`sudo cp` 到服务器 `authelia/` 后 `docker restart authelia`（重启会让现有登录会话失效）
- **密钥**：`secrets/authelia_{jwt_secret,session_secret,storage_key}.txt`

### 4. Gitea (Git仓库服务)
- **版本**：1.21
- **端口**：
  - 内部: 3000 (Web), 22 (SSH)
  - 宿主机仅开放 SSH `${GITEA_SSH_PORT}` (默认 2222)；Web 只走 Traefik 域名
- **功能**：
  - Git仓库托管
  - Gitea Actions (CI/CD)
  - 代码审查、Issues、Wiki
- **配置**：
  - 使用PostgreSQL存储数据
  - 禁用公开注册
  - 需要登录才能查看

### 5. Gitea Runner (CI/CD执行器)
- **功能**：执行Gitea Actions工作流
- **标签**：
  - `ubuntu-latest`
  - `ubuntu-22.04`
  - `ubuntu-24.04`
- **配置**：
  - 全局范围runner
  - 使用Docker执行任务
  - 访问宿主机Docker socket

## 网络架构

### 外部网络
- **traefik**：所有需要外部访问的服务

### 内部网络
- **internal**：服务间内部通信（PostgreSQL、Gitea等）

## 数据持久化

### Docker Volumes
- `traefik_acme` - SSL证书存储
- `postgres_data` - 数据库文件
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
| Gitea | `git.${BASE_DOMAIN}` | Git仓库Web界面 |
| Authelia | `auth.${BASE_DOMAIN}` | 统一登录页 |

**说明**: 域名通过 `.env` 文件中的 `BASE_DOMAIN` 变量配置。例如设置 `BASE_DOMAIN=example.com`，则 Traefik 域名为 `traefik.example.com`。

## 服务依赖关系

```
Traefik (反向代理层)
  ├─ Authelia
  └─ Gitea → PostgreSQL

PostgreSQL (数据层)
  └─ Gitea → Gitea Runner
```

## 访问地址汇总

### 管理界面
- **Traefik**: https://traefik.your-domain.com (Authelia 登录)
- **Gitea**: https://git.your-domain.com
- **Authelia**: https://auth.your-domain.com

### 数据库
- **PostgreSQL**: 仅内网 `postgres:5432`，本机经 SSH 隧道访问

### SSH访问
- **Gitea SSH**: `git.your-domain.com:2222`（直连: `<IP>:${GITEA_SSH_PORT}`，默认 2222）

**注意**: 将 `your-domain.com` 替换为你在 `.env` 中配置的 `BASE_DOMAIN` 实际值。

## 健康检查

所有服务配置了健康检查机制：
- **PostgreSQL**: 每10秒检查 `pg_isready`
- **Gitea**: 每10秒检查HTTP可用性
