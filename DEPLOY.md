# AI 部署指南 — WorkBuddy-DevTop

> **本文件供 AI Agent 读取执行。** 当用户要求部署 workbuddy-devtop 时，AI 按以下步骤操作即可完成部署并生成访问链接。

---

## 适用场景

- **WorkBuddy / CloudStudio 沙箱环境**：用户在一个全新的远程虚拟环境中，需要通过 AI 部署桌面
- **本地服务器**：用户在有 Docker 的本地机器上手动部署
- **其他容器环境**：任何支持 Docker 的 Linux 环境

## 前置条件检查

开始前先确认环境：

```bash
# 确认 Docker 可用
docker --version
docker compose version

# 确认 /workspace 目录存在（WorkBuddy 环境通常有）
ls -d /workspace 2>/dev/null

# 检测是否为 CloudStudio 沙箱环境
echo "X_IDE_SPACE_KEY=${X_IDE_SPACE_KEY:-未设置}"
```

---

## 部署流程

### 第 1 步：克隆仓库

```bash
cd /workspace
git clone https://cnb.cool/aican.do/workbuddy-devtop.git
cd workbuddy-devtop
```

> 如果 `/workspace/workbuddy-devtop` 已存在，直接 `cd /workspace/workbuddy-devtop` 并 `git pull` 更新。

### 第 2 步：启动容器

```bash
docker compose up -d
```

等待约 15-30 秒让桌面环境初始化完成。

### 第 3 步：健康检查

```bash
# 等待 HTTP 服务就绪（最多 60 秒）
for i in $(seq 1 12); do
  if curl -sI http://localhost:3000 2>&1 | grep -q "401\|200"; then
    echo "✅ 服务已就绪"
    break
  fi
  echo "等待启动... ($i/12)"
  sleep 5
done
```

### 第 4 步：生成访问链接

根据部署环境生成对应的访问 URL：

```bash
# 自动检测环境并生成访问链接
if [ -n "$X_IDE_SPACE_KEY" ]; then
  # CloudStudio 沙箱环境
  ACCESS_URL="https://webview.e2b.${X_IDE_PREVIEW_DOMAIN}/?x-cs-sandbox-id=${X_IDE_SPACE_KEY}&x-cs-sandbox-port=3000"
else
  # 本地或其他服务器环境
  ACCESS_URL="http://localhost:3000"
fi
echo "$ACCESS_URL"
```

**环境说明：**

| 环境 | 检测条件 | 访问 URL 格式 |
|---|---|---|
| CloudStudio 沙箱 | `$X_IDE_SPACE_KEY` 存在 | `https://webview.e2b.<域名>/?x-cs-sandbox-id=<ID>&x-cs-sandbox-port=3000` |
| 本地服务器 | 无该环境变量 | `http://localhost:3000` 或 `http://<服务器IP>:3000` |

> ⚠️ CloudStudio 沙箱环境必须绑定 `0.0.0.0:3000:3000`（docker-compose.yml 默认已配置），否则反向代理无法到达容器。

### 第 5 步：输出部署信息

向用户展示以下信息：

```
✅ WorkBuddy-DevTop 部署完成！

🔗 访问地址：<ACCESS_URL>
🔑 用户名：admin
🔑 密码：GHT8xU0rvraxMxqjozwF

💡 首次加载约需 10-20 秒，请耐心等待。
💡 建议修改默认密码：编辑 docker-compose.yml 中的 PASSWORD 后重启。
```

---

## 环境要求

| 项目 | 要求 |
|---|---|
| Docker | 20+ |
| Docker Compose | v2+ |
| 内存 | 4GB（推荐 8GB） |
| 磁盘 | 10GB+ 可用空间 |
| 端口 | 3000（HTTP）、3001（HTTPS）可用 |

## 常见问题处理

### 端口被占用

```bash
# 查看占用 3000 端口的容器
docker ps --filter publish=3000
# 停止旧容器后重试
```

### 容器启动后无法访问

```bash
# 检查容器状态
docker compose ps
# 查看日志
docker compose logs --tail 50 workbuddy-devtop
# 确认端口绑定是 0.0.0.0:3000:3000（不能是 127.0.0.1）
```

### CloudStudio 沙箱中无法访问

确保 `docker-compose.yml` 中端口绑定为 `0.0.0.0:3000:3000`（默认已是此配置）。

### 修改密码

编辑 `docker-compose.yml` 中的 `PASSWORD` 环境变量，然后：

```bash
docker compose down && docker compose up -d
```

## 运维命令速查

```bash
docker compose ps                          # 查看状态
docker compose logs -f workbuddy-devtop    # 实时日志
docker compose restart workbuddy-devtop    # 重启
docker compose down                        # 停止
docker compose up -d                       # 启动
docker exec -it workbuddy-devtop /bin/bash # 进入容器
docker compose pull && docker compose up -d # 更新镜像
```
