# AI 部署指南 — WorkBuddy-DevTop

> **本文件供 AI Agent 读取执行。** 当用户要求部署 workbuddy-devtop 时，AI 按本文件步骤操作即可完成部署并生成访问链接。

---

## 部署流程

### 第 1 步：克隆仓库

```bash
cd /workspace
git clone https://cnb.cool/aican.do/workbuddy-devtop.git
cd workbuddy-devtop
```

如果 `/workspace` 目录已有同名文件夹，直接进入即可。

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

#### 环境 A：CloudStudio 沙箱（自动检测）

```bash
if [ -n "$X_IDE_SPACE_KEY" ]; then
  ACCESS_URL="https://webview.e2b.${X_IDE_PREVIEW_DOMAIN}/?x-cs-sandbox-id=${X_IDE_SPACE_KEY}&x-cs-sandbox-port=3000"
fi
```

#### 环境 B：本地 / 其他服务器

```bash
ACCESS_URL="http://localhost:3000"
# 或替换为服务器公网 IP
# ACCESS_URL="http://<服务器IP>:3000"
```

### 第 5 步：输出部署信息

向用户展示：

```
✅ WorkBuddy-DevTop 部署完成！

🔗 访问地址：<ACCESS_URL>
🔑 用户名：admin
🔑 密码：GHT8xU0rvraxMxqjozwF

💡 首次加载约需 10-20 秒，请耐心等待。
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
