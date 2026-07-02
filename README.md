# WorkBuddy-DevTop

> 在任何支持 Docker 的环境中一键拉起的**云端中文开发桌面**。
>
> 浏览器访问即得完整 XFCE 桌面，自带密码保护、中文输入法、开发工具链和 Docker-in-Docker。

基于 [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) 架构与 `devtop/base` 镜像，针对 CloudStudio 沙箱等容器环境做了适配优化。

---

## ✨ 核心特性

| 特性 | 说明 |
|---|---|
| 🖥️ **完整桌面** | XFCE 4.20 + Wayland，浏览器直接访问，体验接近本地 |
| 🇨🇳 **中文优先** | `zh_CN.UTF-8` locale + Noto CJK 字体 + fcitx5 拼音输入法自启动 |
| 🔐 **密码保护** | nginx HTTP 基础认证，公网暴露也不裸奔 |
| 🐳 **Docker-in-Docker** | 共享宿主 `docker.sock`，容器内直接操作宿主 Docker |
| 📁 **目录互通** | 宿主工作目录挂载进桌面，文件双向可见 |
| 🔧 **自动修复** | 启动脚本自动处理环境兼容问题（见下文） |
| ⚡ **中国镜像加速** | APT / pip / npm / Go / Cargo / Docker 全部换源 |
| 🛠️ **开发全家桶** | Python 3.14 + Node 22 + Go + Rust + Bun + code-server + Git + 完整编译链 |

---

## 🚀 快速开始

### 前置要求

- Docker + Docker Compose
- 2核 CPU / 4GB 内存（推荐 4核 / 8GB）
- 5GB+ 可用磁盘

### 三步启动

```bash
# 1. 克隆仓库
git clone https://cnb.cool/aican.do/workbuddy-devtop.git
cd workbuddy-devtop

# 2. 按需修改密码（可选）
# 编辑 docker-compose.yml 中的 PASSWORD 环境变量

# 3. 启动
docker compose up -d
```

启动���访问 **http://localhost:3000**，输入用户名密码即可进入桌面。

### 访问地址

| 环境 | URL |
|---|---|
| 本地部署 | `http://localhost:3000` |
| CloudStudio 沙箱 | `https://webview.e2b.${X_IDE_PREVIEW_DOMAIN}/?x-cs-sandbox-id=${X_IDE_SPACE_KEY}&x-cs-sandbox-port=3000` |

> ⚠️ 推荐使用 HTTP (3000) 而非 HTTPS (3001)，避免自签名证书问题。

### 默认凭据

| 项目 | 值 |
|---|---|
| 用户名 | `admin` |
| 密码 | `GHT8xU0rvraxMxqjozwF` |

> 🔔 **请务必修改默认密码！** 编辑 `docker-compose.yml` 中的 `PASSWORD` 变量后重启容器。

---

## 📁 项目结构

```
workbuddy-devtop/
├── docker-compose.yml              # 核心部署配置
├── devtop-init-fix.sh              # 启动时自动修复脚本（挂载到 /custom-cont-init.d/）
├── devtop-hotfix.sh                # 一次性运行时热修复脚本（手动执行）
├── webtop-env.md                   # 中文输入法使用说明（桌面快捷方式指向）
├── deploy-info.txt                 # 快速参考信息卡
├── .gitignore
├── LICENSE
└── README.md                       # 本文件
```

> `config/` 目录是容器运行时自动生成的用户数据（桌面配置、缓存等），**不纳入版本控制**，首次启动会自动创建。

---

## ⚙️ 配置说明

### docker-compose.yml 关键配置项

| 配置 | 说明 | 默认值 |
|---|---|---|
| `image` | 镜像地址 | `docker.cnb.cool/fuliai/devtop/base:v1.6` |
| `CUSTOM_USER` | 登录用户名 | `admin` |
| `PASSWORD` | 登录密码 | `GHT8xU0rvraxMxqjozwF` |
| `PUID` / `PGID` | 容器内用户 UID/GID | `1000` / `1000` |
| `TZ` | 时区 | `Asia/Shanghai` |
| `LC_ALL` | 语言环境 | `zh_CN.UTF-8` |
| `shm_size` | 共享内存大小（桌面稳定性关键） | `5gb` |
| `seccomp:unconfined` | 关闭 seccomp 限制（GUI 兼容需要） | - |

### 卷挂载

| 挂载路径 | 用途 |
|---|---|
| `./config:/config` | 用户配置持久化 |
| `/workspace:/workspace` | 宿主工作目录互通（按需修改） |
| `/var/run/docker.sock:/var/run/docker.sock` | 共享宿主 Docker（按需修改） |
| `./devtop-init-fix.sh:/custom-cont-init.d/...` | 启动修复脚本 |

---

## 🔧 自动修复脚本

`devtop-init-fix.sh` 通过 linuxserver 的 `/custom-cont-init.d/` 机制在容器每次启动时自动执行，解决以下问题：

| # | 修复项 | 说明 | 影响平台 |
|---|---|---|---|
| 1 | dockremap 用户冲突 | CloudStudio 宿主 userns-remap 导致 uid=1000 冲突 | CloudStudio |
| 2 | zsh/oh-my-zsh 配置 | 空目录挂载时 zsh 自动生成空 .zshrc 覆盖默认配置 | 所有平台 |
| 3 | hardinfo2 缺失依赖 | 安装 mesa-utils + dmidecode，消除"未正确打包"警告 | 所有平台 |
| 4 | fcitx5 自启动 | 确保中文输入法随桌面启动 | 所有平台 |

> 在非 CloudStudio 平台上运行也是安全的 — 修复 1 为 no-op，修复 2/3/4 只在缺失时才执行。

---

## 🛠️ 运维命令

```bash
# 启动 / 停止 / 重启
docker compose up -d
docker compose down
docker compose restart workbuddy-devtop

# 查看状态和日志
docker compose ps
docker compose logs -f workbuddy-devtop

# 进入容器
docker exec -it workbuddy-devtop /bin/bash

# 以桌面用户身份进入
docker exec -it workbuddy-devtop bash -c "su - aican.do"

# 更新镜像
docker compose pull && docker compose up -d
```

---

## 🌐 CloudStudio 沙箱部署

在 CloudStudio 沙箱环境中部署时，需要注意以下适配：

1. **端口绑定**：必须使用 `0.0.0.0:3000:3000`（非默认的 `127.0.0.1`），沙箱反向代理才能到达容器
2. **shm_size**：默认 1gb 会导致桌面崩溃，需设为 `5gb`
3. **seccomp**：需设为 `unconfined`，否则 GUI 程序可能异常
4. **docker.sock**：沙箱宿主的 Docker 可通过挂载 `/var/run/docker.sock` 直接使用
5. **userns-remap**：沙箱宿主启用了用户重映射，init 脚本会自动处理

---

## 🇨🇳 中文输入法

桌面启动后，fcitx5 拼音输入法会自动启动。

| 快捷键 | 功能 |
|---|---|
| `Ctrl+Space` | 切换中英文输入 |
| `Shift` | 临时切换英文（中文模式下） |
| `Ctrl+.` | 切换全角/半角标点 |

如输入法未启动，终端执行：

```bash
fcitx5 -d --replace
```

详细说明见 [webtop-env.md](webtop-env.md)。

---

## 📋 镜像内容

基于 `devtop/base:v1.6`（Ubuntu 26.04 LTS），预装：

<details>
<summary>点击展开完整清单</summary>

### 开发语言

| 语言 | 版本 |
|---|---|
| Python | 3.14.4 (uv 管理) |
| Node.js | 22.22.3 (LTS) |
| Go | 1.24.4 |
| Rust | 1.95.0 |
| Bun | 1.3.13 |

### 开发工具

| 工具 | 说明 |
|---|---|
| Docker | 29.5.3 + compose + buildx |
| Git | 2.53.0 + git-lfs |
| code-server | 已安装 + 16 个扩展（含中文语言包） |
| Codex CLI | @openai/codex AI 编程助手 |
| 编译工具链 | gcc 15.2, g++, clang, lldb, cmake 4.2, meson, ninja, ccache |

### CLI 增强工具

fzf, bat(eza), ripgrep, fd, jq, yq, direnv, tmux, tldr, btop, htop

### 数据库客户端

sqlite3, postgresql-client, mariadb-client, redis-tools

### 中文环境

- Locale: `zh_CN.UTF-8`
- 字体: Noto Sans/Serif CJK SC + 文泉驿微米黑/正黑
- 输入法: fcitx5 5.1.19 + chinese-addons + pinyin
- 桌面语言: 中文

</details>

---

## 📄 相关文档

| 文档 | 说明 |
|---|---|
| [webtop-env.md](webtop-env.md) | 中文输入法使用说明 |

---

## 📜 License

MIT License - 详见 [LICENSE](LICENSE)

---

## 🙏 鸣谢

- [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop) — Webtop 基础架构
- [devtop/base](https://cnb.cool/fuliai/devtop) — 基础镜像
- [fcitx5](https://fcitx-im.org/) — 中文输入法框架
- [oh-my-zsh](https://ohmyz.sh/) — Shell 体验增强
