# Webtop 部署与沙箱公开访问 — 完整实操经验

> 在 CloudStudio 沙箱内部署 `linuxserver/webtop:ubuntu-xfce`，通过沙箱泛域名反代对外公开访问。基于参考材料 + 一轮完整实战，补充踩坑细节、优化建议和排错方法。**可直接复现。**

---

## 一、环境前提

| 项 | 说明 |
|---|---|
| 沙箱 | CloudStudio CodeBuddy，`bj5` 区域，`/workspace` 持久化 |
| Docker | `docker --version` → 27.5.1，`docker compose version` → v2.33.0 |
| 网络 | 沙箱内可访问公网（拉镜像）、可访问 `127.0.0.1`（容器端口） |
| 架构 | x86-64，32 核 CPU，支持 AVX2（Wayland 可用） |

```bash
# 第一步永远先确认这两条
docker --version
docker compose version
```

---

## 二、镜像选择

### 2.1 镜像源

| 镜像源 | 地址 | 说明 |
|---|---|---|
| **推荐（本次使用）** | `linuxserver/webtop:ubuntu-xfce` | Docker Hub，无拉取限制 |
| 官方 registry | `lscr.io/linuxserver/webtop:ubuntu-xfce` | 有限流（`toomanyrequests`），沙箱 IP 容易被限 |

> **本次实测**：`docker pull linuxserver/webtop:ubuntu-xfce` 一次成功，无任何限流，镜像约 1.5GB，拉取耗时约 2 分钟（取决于网络）。

### 2.2 桌面版本选择

用户需求是 Ubuntu XFCE，对应 tag 为 `ubuntu-xfce`。完整可用 tag 列表：

| Tag | 基础系统 | 桌面 | Wayland |
|---|---|---|---|
| `latest` | Alpine | XFCE | ✅ |
| `ubuntu-xfce` | Ubuntu | XFCE | ✅ |
| `ubuntu-kde` | Ubuntu | KDE | ✅（仅 Wayland） |
| `ubuntu-i3` | Ubuntu | i3 | ✅ |
| `ubuntu-mate` | Ubuntu | MATE | — |
| `debian-xfce` | Debian | XFCE | ✅ |
| `fedora-xfce` | Fedora | XFCE | ✅ |
| `arch-xfce` | Arch | XFCE | ✅ |

---

## 三、docker-compose 配置（逐项说明）

```yaml
---
services:
  webtop:
    image: linuxserver/webtop:ubuntu-xfce   # ① Docker Hub 源，无拉取限制
    container_name: webtop
    security_opt:
      - seccomp:unconfined                  # ② GUI 兼容性，README 明确要求
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai                    # ③ 时区
      - CUSTOM_USER=admin                   # ④ HTTP 基础认证用户名
      - PASSWORD=<强密码>                   # ⑤ 设置后自动启用 nginx auth_basic
      - LC_ALL=zh_CN.UTF-8                  # ⑥ 中文桌面语言
    volumes:
      - ./config:/config                    # ⑦ 持久化用户主目录
    ports:
      - 0.0.0.0:3000:3000                  # ⑧ 必须 0.0.0.0，否则沙箱反代进不来
      - 0.0.0.0:3001:3001                  #    3000=HTTP，3001=HTTPS
    shm_size: "1gb"                         # ⑨ 桌面镜像必需，防花屏/崩溃
    restart: unless-stopped                 # ⑩ 沙箱休眠后自动恢复
```

### 逐项解释

| # | 配置 | 为什么 |
|---|---|---|
| ① | `linuxserver/webtop:ubuntu-xfce` | Docker Hub 源，不受 `lscr.io` 限流影响 |
| ② | `seccomp:unconfined` | 现代 GUI 在 Docker 默认 seccomp 下可能 syscall 受限，README 明确建议 |
| ③ | `TZ=Asia/Shanghai` | 桌面时钟显示正确时区 |
| ④ | `CUSTOM_USER=admin` | HTTP 基础认证用户名，配合 PASSWORD 启用认证 |
| ⑤ | `PASSWORD=<强密码>` | 镜像内置 nginx 脚本检测此变量，自动取消 `auth_basic` 注释启用认证 |
| ⑥ | `LC_ALL=zh_CN.UTF-8` | 桌面菜单、文件管理器等显示中文 |
| ⑦ | `./config:/config` | webtop 用户主目录在 `/config`，持久化后重建容器不丢桌面设置 |
| ⑧ | `0.0.0.0:3000:3000` | **核心配置**。绑定所有网卡，沙箱反代才能把流量送入容器。不能只绑 `127.0.0.1` |
| ⑨ | `shm_size: "1gb"` | 桌面环境共享内存不足会闪退/花屏，官方推荐下限 |
| ⑩ | `restart: unless-stopped` | 异常退出自动重启，手动 `docker compose down` 后不重启 |

### 端口选择：3000（HTTP） vs 3001（HTTPS）

选择 **3000 端口**（HTTP）作为公开访问入口：

- 沙箱反代网关本身已是 HTTPS，浏览器侧 secure context 满足（WebCodecs 可用）
- 到后端走 HTTP 避开 webtop 自签证书校验问题
- 省一层证书折腾，减少故障点

### 密码生成

```bash
# 生成 20 位强随机密码
python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(20)))"
```

---

## 四、镜像内置的反代/认证机制

这是关键经验——**不用自己写 Nginx/Caddy 反代配置**。linuxserver/webtop 镜像（基于 Selkies）在启动脚本里已内置支持。

通过 `docker exec webtop cat /etc/s6-overlay/s6-rc.d/init-nginx/run` 可看到 nginx 配置动态生成的逻辑：

| 环境变量 | 作用 | 默认值 |
|---|---|---|
| `PASSWORD` | 设置后自动启用 nginx HTTP 基础认证 | 空（不认证） |
| `CUSTOM_USER` | 认证用户名 | `abc` |
| `SUBFOLDER` | 子路径前缀 | `/` |
| `CUSTOM_PORT` | 容器内 HTTP 监听端口 | `3000` |
| `CUSTOM_HTTPS_PORT` | 容器内 HTTPS 监听端口 | `3001` |
| `LC_ALL` | 桌面语言 | `en` |
| `HARDEN_DESKTOP` | 硬化模式：关 sudo/终端/文件传输 | `false` |

> ⚠️ **公开访问必备**：至少设 `PASSWORD`。否则任何人拿到 URL 即获得容器内 root（终端免密 sudo）。

---

## 五、CloudStudio 沙箱反代机制

### 5.1 域名拼接

```
host = "webview.e2b." + ${X_IDE_PREVIEW_DOMAIN}
url  = "https://${host}/?x-cs-sandbox-id=${X_IDE_SPACE_KEY}&x-cs-sandbox-port=${PORT}"
```

### 5.2 获取环境变量

```bash
# 方法一：直接读进程环境（推荐）
echo $X_IDE_SPACE_KEY       # 本次：69614783008d4dbaaf5607cea768c5b8
echo $X_IDE_PREVIEW_DOMAIN  # 本次：bj5.sandbox.cloudstudio.club

# 方法二：envd 兜底（进程环境没有时）
curl -s http://127.0.0.1:49983/envs
```

> **补充**：沙箱区域不固定，本次为 `bj5`，不同沙箱可能为 `sh1`、`gz` 等。**每次新建沙箱环境变量都会变**，不要硬编码。

### 5.3 反代路由流程

```
浏览器请求（带 query 参数）
  ↓
CloudStudio Gateway 解析 query:
  x-cs-sandbox-id   → 定位沙箱容器
  x-cs-sandbox-port → 转发到容器对应端口
  ↓
302 响应 + Set-Cookie:
  x-cs-sandbox-id=...; x-cs-sandbox-port=...; HttpOnly; Secure
  Location: /
  ↓
浏览器存 cookie，后续请求自动携带
  ↓
网关据 cookie 路由 → 容器 0.0.0.0:3000
  ↓
容器内 nginx（auth_basic 认证）→ Selkies/WebRTC 桌面
```

- 首次必须带 query 参数，cookie 写入后才能访问根路径
- 浏览器自动处理 cookie 和重定向，用户直接点 URL 即可

### 5.4 WebSocket 透传

桌面视频/输入信令走 WebSocket。实测三层网关（CloudStudio Gateway → 容器内 nginx）全透传：

- `/websocket` 升级握手 → `HTTP/1.1 101 Switching Protocols` ✅
- 注意：WebSocket 必须走 HTTP/1.1。浏览器默认使用 HTTP/1.1，正常使用无影响

---

## 六、验证方法（完整测试矩阵）

部署后建议按以下顺序逐层验证：

### 6.1 容器状态检查

```bash
cd /workspace
docker compose ps
# 期望：STATUS=Up，PORTS=0.0.0.0:3000-3001->3000-3001/tcp
```

### 6.2 容器内直连测试

```bash
# 不带认证 → 应返回 401（认证已生效）
curl -s -o /dev/null -w "code=%{http_code}\n" http://127.0.0.1:3000/
# 期望: code=401

# 带认证 → 应返回 200
curl -s -u "admin:<密码>" -o /dev/null -w "code=%{http_code}\n" http://127.0.0.1:3000/
# 期望: code=200
```

> **补充说明**：401 表示 nginx `auth_basic` 已正确启用。这是**好事**——说明认证生效。

### 6.3 公开 URL 测试

```bash
HOST="webview.e2b.${X_IDE_PREVIEW_DOMAIN}"
SID="${X_IDE_SPACE_KEY}"
URL="https://${HOST}/?x-cs-sandbox-id=${SID}&x-cs-sandbox-port=3000"

# HTTP 前端页面测试（带认证 + cookie jar）
curl -sk -L -c /tmp/cj.txt -b /tmp/cj.txt \
  -u "admin:<密码>" \
  -o /dev/null -w "code=%{http_code}\n" "$URL"
# 期望: code=200
```

### 6.4 WebSocket 握手测试

#### 本地直连（稳定可靠）

```bash
timeout 10 curl -sk --http1.1 \
  -u "admin:<密码>" \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -D - -o /dev/null http://127.0.0.1:3000/websocket 2>&1
# 期望: HTTP/1.1 101 Switching Protocols
#       Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

> **补充经验**：`curl` 测试 WebSocket 握手后会挂起等待帧数据，这是正常行为，加 `timeout` 可避免卡死。

#### 公开 URL WebSocket

```bash
timeout 15 curl -sk --http1.1 -L \
  -u "admin:<密码>" \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -D - -o /dev/null \
  "https://${HOST}/websocket?x-cs-sandbox-id=${SID}&x-cs-sandbox-port=3000" 2>&1
# 期望: 302（设置 cookie）+ 后续响应
```

> **补充说明**：公开 URL 的 WS 测试在 curl 中可能不完美（网关先返回 302 设置 cookie，curl 的 cookie 传递在 WS 升级场景下有限制），但**浏览器中完全正常**。本地 101 测试通过即可确认 WebSocket 功能正常。

### 6.5 浏览器人工验证（最终确认）

在浏览器中打开公开 URL，确认：
- [x] 弹出 HTTP 基础认证框，输入凭据后进入桌面
- [x] 桌面正常渲染（XFCE 桌面 + 底部面板）
- [x] 鼠标/键盘输入响应正常
- [x] WebRTC 视频流流畅（按 `Ctrl+Alt+Shift+S` 可查看编码统计）

---

## 七、本次实际部署数据

| 项目 | 实际值 | 备注 |
|---|---|---|
| 沙箱区域 | `bj5` | **非固定**，每次新建可能不同 |
| 沙箱 ID | `69614783008d4dbaaf5607cea768c5b8` | 每次新建沙箱会变 |
| 反代域名 | `webview.e2b.bj5.sandbox.cloudstudio.club` | 按公式拼接 |
| 镜像 | `linuxserver/webtop:ubuntu-xfce` | Docker Hub |
| 拉取耗时 | ~2 分钟 | 取决于网络 |
| 启动初始化 | ~8 秒 | `docker compose up -d` 到可访问 |
| 分辨率 | 1910×924 | 自适应 |
| 编码 | H264 (CPU) FullFrame, 60 FPS | 32 核 CPU |
| 色彩空间 | I420 (Limited Range) | — |
| 持久化路径 | `/workspace/config/` | 容器重建不丢 |

---

## 八、对参考文档的补充与修正

以下是根据本次实际部署过程，对原始参考文档的补充和细节修正：

### 8.1 补充内容

| # | 补充点 | 说明 |
|---|---|---|
| 1 | **沙箱区域非固定** | 参考文档写 `sh1`，本次实际为 `bj5`。每次新建沙箱的区域都可能不同，必须从环境变量动态获取 |
| 2 | **envd 兜底方案已验证** | `curl -s http://127.0.0.1:49983/envs` 确实能返回完整环境变量 JSON，可作为备选方案 |
| 3 | **认证测试方法** | 先测不带认证的 401，再测带认证的 200——分两步确认认证链路正确 |
| 4 | **WS 测试分层** | 先测本地 101，确认容器内 WebSocket 正常；再测公开 URL。本地通过即可信任浏览器场景 |
| 5 | **启动等待时间** | 建议 `docker compose up -d` 后等 8~10 秒再验证，容器内 nginx + Selkies + 桌面需要初始化 |
| 6 | **密码生成** | 使用 Python `secrets` 模块生成强密码，记录在部署信息文件中 |
| 7 | **LC_ALL 语言设置** | Ubuntu XFCE 镜像支持中文桌面，设置 `LC_ALL=zh_CN.UTF-8` 即可 |

### 8.2 修正/澄清

| # | 参考文档原文 | 本次实测 |
|---|---|---|
| 1 | 使用 `CUSTOM_USER` 变量名 | 官方的变量是 `CUSTOM_USER`，应统一使用 `CUSTOM_USER`。nginx init 脚本中读取的是 `CUSTOM_USER` |
| 2 | `latest` tag（Alpine XFCE） | 按需求使用 `ubuntu-xfce` tag。不同 tag 的基础系统不同，包管理器也不同 |
| 3 | WS 测试不设 timeout | 必须加 `timeout`，否则 WebSocket 升级后连接保持打开，curl 会一直挂起 |

---

## 九、常见问题与排错

| 现象 | 原因 | 解决 |
|---|---|---|
| `toomanyrequests` 拉镜像失败 | `lscr.io` 限流 | 改用 `linuxserver/webtop:ubuntu-xfce`（Docker Hub） |
| 公开 URL 返回 404 | 首次未带 query 参数 | URL 必须含 `?x-cs-sandbox-id=...&x-cs-sandbox-port=...` |
| 根路径 404 但带 query 能访问 | cookie 未写入/丢失 | 清浏览器 cookie 重新带 query 访问一次 |
| 容器启动但反代进不去 | 端口绑了 `127.0.0.1` | compose 里写 `0.0.0.0:3000:3000`，重建容器 |
| 桌面花屏/崩溃 | shm 不足 | `shm_size: "1gb"` 或更大 |
| Wayland 不启动 | CPU 不支持 AVX2（老 CPU） | 自动回退 X11，或设 `PIXELFLUX_WAYLAND=false` |
| 访问返回 401 | 认证已生效（正常现象！） | 输入正确的用户名密码 |
| WS curl 测试挂起不返回 | WebSocket 长连接特性 | 加 `timeout 10` 限制执行时间 |
| 镜像拉取慢 | 沙箱网络波动 | 耐心等，或换时间段重试 |

---

## 十、运维命令速查

```bash
cd /workspace

# 状态
docker compose ps

# 实时日志
docker compose logs -f webtop

# 重启（修改配置后）
docker compose restart webtop

# 停止 + 删除容器（数据保留在 ./config）
docker compose down

# 重新创建并启动
docker compose up -d

# 更新镜像
docker compose pull && docker compose up -d

# 进入容器 shell
docker exec -it webtop /bin/bash

# 查看容器版本
docker inspect -f '{{ index .Config.Labels "build_version" }}' webtop

# 清理旧镜像
docker image prune
```

---

## 十一、安全清单

| 级别 | 措施 | 说明 |
|---|---|---|
| **必需** | 设 `PASSWORD` | nginx 基础认证，最低安全要求 |
| **建议** | 使用强密码 | 20 位以上随机字符 |
| **注意** | 沙箱休眠后 URL 失效 | 需重新获取环境变量拼接新 URL |
| **警告** | 终端免密 sudo | 别把 URL 发给不可信的人 |
| **进阶** | `HARDEN_DESKTOP=true` | 关闭 sudo/终端/文件传输 |
| **高阶** | 前置 SWAG 反代 + 强认证 | 参考 linuxserver/swag |

---

## 十二、交付物

| 文件 | 说明 |
|---|---|
| `/workspace/docker-compose.yml` | 部署配置 |
| `/workspace/config/` | 持久化数据（桌面设置、用户文件） |
| `/workspace/deploy-info.txt` | 部署信息（URL、凭据，每次部署更新） |

---

## 十三、快速部署脚本

将以上流程整合为一条命令（需替换密码）：

```bash
# 1. 生成配置
cat > /workspace/docker-compose.yml << 'EOF'
---
services:
  webtop:
    image: linuxserver/webtop:ubuntu-xfce
    container_name: webtop
    security_opt:
      - seccomp:unconfined
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - CUSTOM_USER=admin
      - PASSWORD=请替换为强密码
      - LC_ALL=zh_CN.UTF-8
    volumes:
      - ./config:/config
    ports:
      - 0.0.0.0:3000:3000
      - 0.0.0.0:3001:3001
    shm_size: "1gb"
    restart: unless-stopped
EOF

# 2. 拉取 + 启动
cd /workspace && docker compose up -d

# 3. 等待初始化
sleep 10

# 4. 验证
curl -s -o /dev/null -w "Local: %{http_code}\n" http://127.0.0.1:3000/
echo "Public URL: https://webview.e2b.${X_IDE_PREVIEW_DOMAIN}/?x-cs-sandbox-id=${X_IDE_SPACE_KEY}&x-cs-sandbox-port=3000"
```
