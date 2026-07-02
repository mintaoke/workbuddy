# Devtop Base v1.5 镜像 — 深度检查报告与优化迭代方案

> 基于 `docker.cnb.cool/fuliai/devtop/base:v1.5` 镜像的实际部署与容器内深度检查，给出完整的优化建议。
> 检查日期：2026-07-01 | 镜像大小：9.05GB | 基础系统：Ubuntu 26.04 LTS

---

## 一、镜像现状概览

### 1.1 基础环境

| 项目 | 实际值 | 评价 |
|---|---|---|
| 基础系统 | Ubuntu 26.04 LTS (Resolute Raccoon) | ✅ 最新 |
| 桌面环境 | XFCE 4.20 + Wayland (Labwc) | ✅ 现代化 |
| 默认 Shell | zsh + oh-my-zsh + autosuggestions + syntax-highlighting | ✅ 优秀 |
| 用户 | abc (uid=1000), groups: sudo, docker, users | ✅ 合理 |
| Locale | `zh_CN.UTF-8`（全量设置） | ✅ 中文优先 |
| 时区 | `Asia/Shanghai` | ✅ 正确 |
| 镜像大小 | 9.05GB | ⚠️ 偏大，有优化空间 |

### 1.2 已安装开发工具（优秀）

| 语言/工具 | 版本 | 说明 |
|---|---|---|
| Python | 3.14.4 (uv 管理) | 最新 |
| Node.js | 22.22.3 (nodesource) | LTS |
| Go | 1.24.4 | 较新 |
| Rust | 1.95.0 (rustc + cargo) | 最新 |
| Bun | 1.3.13 | 现代 JS 运行时 |
| Docker | 29.5.3 + compose + buildx | 容器内 DinD |
| Git | 2.53.0 + git-lfs | 最新 |
| code-server | 已安装 + 16 个扩展 | 含中文语言包 |
| Codex CLI | 0.139.0 (@openai/codex) | AI 编程助手 |
| 编译工具链 | gcc 15.2, g++, clang, lldb, cmake 4.2, meson, ninja, ccache | 完整 |
| CLI 增强工具 | fzf, bat(eza), ripgrep, fd, jq, yq, direnv, tmux, tldr, btop, htop | 优秀 |
| 数据库客户端 | sqlite3, postgresql-client, mariadb-client, redis-tools | 齐全 |

### 1.3 中文支持现状

| 项目 | 状态 | 详情 |
|---|---|---|
| Locale | ✅ | `zh_CN.UTF-8` 全量配置 |
| 中文字体 | ✅ | Noto Sans/Serif CJK SC + 文泉驿微米黑/正黑（35 个字体文件） |
| fontconfig | ✅ | sans-serif/serif/monospace 均优先 CJK |
| 输入法框架 | ✅ 已安装 | fcitx5 5.1.19 + chinese-addons + pinyin |
| 输入法配置 | ✅ | 拼音（拆字/符号/英文候选词已启用），双拼自然码 |
| 输入法环境变量 | ✅ | GTK_IM_MODULE/QT_IM_MODULE/XMODIFIERS 均设为 fcitx |
| **输入法自启动** | ❌ **缺失** | **fcitx5 未配置自启动，桌面启动后无法输入中文** |
| Chromium 语言 | ✅ | accept_languages=zh-CN,zh,en-US,en |
| Git 中文配置 | ✅ | quotepath=false, utf-8 编码 |
| 中文输入帮助 | ❌ **失效** | 桌面快捷方式指向 `/workspace/webtop-env.md`，**该文件不存在** |

---

## 二、问题清单（按严重程度排序）

### 🔴 P0 — 严重问题（影响核心使用）

#### 问题 1：fcitx5 输入法未配置自启动

**现象**：容器启动后，fcitx5 进程未运行，用户无法在桌面输入中文。

**根因**：
- `org.fcitx.Fcitx5.desktop` 仅存在于 `/usr/share/applications/`，**未复制到 `/etc/xdg/autostart/`**
- `/config/.config/autostart/` 目录不存在
- `/defaults/devtop-config/.config/autostart/` 仅有 `codex-desktop.desktop`
- `startwm.sh` 启动 xfce4-session 时未显式启动 fcitx5
- `start-webtop.sh` 中无任何 fcitx 相关逻辑

**影响**：中文用户进入桌面后无法输入中文，必须手动终端执行 `fcitx5 -d`。

**修复方案**（Dockerfile 层面）：

```dockerfile
# 方案 A：复制 desktop 文件到 autostart 目录
RUN cp /usr/share/applications/org.fcitx.Fcitx5.desktop /etc/xdg/autostart/

# 方案 B（更可靠）：在 startwm.sh 中显式启动
# 在 exec dbus-launch ... xfce4-session 之前加入：
# (sleep 2 && fcitx5 -d --replace) &
```

**修复方案**（运行时层面，立即可用）：

```bash
# 在容器内执行
mkdir -p /config/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop /config/.config/autostart/
docker compose restart webtop
```

---

#### 问题 2：中文输入帮助桌面快捷方式失效

**现象**：桌面上的「中文输入验收」快捷方式点击无反应。

**根因**：快捷方式 `Exec=exo-open /workspace/webtop-env.md`，但 `/workspace/webtop-env.md` 文件不存在。

**修复方案**（Dockerfile 层面）：

```dockerfile
# 创建中文输入帮助文档
COPY webtop-env.md /workspace/webtop-env.md
```

或在 `start-webtop.sh` 初始化逻辑中生成该文件。文档内容应包含：
- fcitx5 快捷键说明（Ctrl+Space 切换中英文）
- 拼音输入法使用说明
- 常见问题排查

---

#### 问题 3：所有包管理器使用默认源（非中国镜像）

**现象**：APT、pip、npm、Go、Cargo 全部使用官方默认源，中国用户下载极慢。

**实测数据**：
- `apt-get update`：33 秒，749 kB/s（archive.ubuntu.com）
- `pip install`：2 秒（PyPI，偶然较快但不稳定）
- `npm`：默认 registry.npmjs.org
- `go`：GOPROXY=proxy.golang.org（国内不可达或极慢）
- `cargo`：无镜像配置（默认 crates.io）

**影响**：用户在容器内安装任何软件包都极慢，严重影响开发体验。

**修复方案**：

```dockerfile
# ===== APT 中国镜像（阿里云）=====
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's|http://security.ubuntu.com/ubuntu/|https://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

# ===== pip 镜像（阿里云）=====
RUN mkdir -p /etc/pip.conf.d && \
    printf '[global]\nindex-url = https://mirrors.aliyun.com/pypi/simple/\ntrusted-host = mirrors.aliyun.com\n' > /etc/pip.conf

# ===== npm 镜像（淘宝）=====
RUN npm config set registry https://registry.npmmirror.com

# ===== Go 镜像（七牛）=====
RUN go env -w GOPROXY=https://goproxy.cn,direct

# ===== Cargo 镜像（上海交大）=====
RUN mkdir -p /usr/local/cargo && \
    printf '[source.crates-io]\nreplace-with = "sjtu"\n[source.sjtu]\nregistry = "sparse+https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/"\n' > /usr/local/cargo/config.toml

# ===== Docker 镜像加速 =====
RUN mkdir -p /etc/docker && \
    printf '{"registry-mirrors":["https://docker.mirrors.sjtug.sjtu.edu.cn","https://docker.mirrors.ustc.edu.cn"]}' > /etc/docker/daemon.json
```

---

### 🟡 P1 — 重要缺失（影响完整体验）

#### 问题 4：Hardinfo2（硬件信息）缺失依赖包

**现象**：打开桌面「硬件信息」应用，弹出 **"未正确打包"** 警告框，列出两个缺失的依赖：

| 缺失包 | 提供工具 | 作用 |
|---|---|---|
| `mesa-utils` | `glxinfo` | 获取 GPU/OpenGL 渲染信息 |
| `dmidecode` | `dmidecode` | 读取主板/BIOS/DMI 硬件信息 |

**影响**：
- 硬件信息工具无法正常显示完整系统信息
- 用户体验差，打开即报错

**根因**：Dockerfile 在编译 hardinfo2 时跳过了 `Recommends` 依赖检查，导致可选但重要的包未安装。

**修复方案（Dockerfile 层面）**：

```dockerfile
# 安装 hardinfo2 运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    mesa-utils \
    dmidecode \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

> ⚠️ `dmidecode` 在容器内因无法访问 `/dev/mem` 只能读取部分信息，但安装后警告消失，其余功能正常。这是容器安全限制，无法修复。

**修复方案（运行时）**：

```bash
apt-get update && apt-get install -y mesa-utils dmidecode
```

✅ **已在 v1.6 运行时修复，并固化为 init 脚本自动安装。**

---

#### 问题 5：无媒体播放器和 ffmpeg

**现象**：容器内无 ffmpeg 二进制、无 mpv/vlc 播放器、GStreamer 仅有基础库无插件。

**影响**：无法播放视频/音频，无法进行媒体格式转换，网页视频可能无法播放。

**修复方案**：

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    mpv \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

---

#### 问题 6：无办公软件

**现象**：无 LibreOffice，用户无法查看/编辑 Word/Excel/PPT。

**修复方案**：

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-l10n-zh-cn \
    libreoffice-help-zh-cn \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

> ⚠️ LibreOffice 会增加约 500MB 镜像大小，建议作为可选层或用 proot-apps 安装。

---

#### 问题 7：无常用下载/压缩工具

**缺失工具**：aria2（多线程下载）、rar/unrar（RAR 解压）、sshpass

**修复方案**：

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 \
    unrar \
    rar \
    sshpass \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

---

#### 问题 8：无现代 CLI 工具

**缺失工具**：lazygit（Git TUI）、lazydocker（Docker TUI）、fastfetch（系统信息）

**修复方案**：

```dockerfile
# lazygit
RUN LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/') && \
    curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz" | \
    tar xz -C /usr/local/bin lazygit

# fastfetch
RUN curl -fsSL "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.tar.gz" | \
    tar xz -C /usr/local --strip-components=1 fastfetch-linux-amd64/usr/bin/fastfetch
```

---

#### 问题 9：Chromium 书签过于简单

**现状**：仅有 Webtop、code-server、README 三个书签，无中国常用网站。

**建议添加书签**：

| 网站 | URL |
|---|---|
| 百度 | https://www.baidu.com |
| GitHub | https://github.com |
| Gitee 码云 | https://gitee.com |
| CNB | https://cnb.cool |
| MDN Web Docs | https://developer.mozilla.org/zh-CN |
| 掘金 | https://juejin.cn |
| Stack Overflow | https://stackoverflow.com |

---

### 🟢 P2 — 增强建议（锦上添花）

#### 建议 9（原）：硬信息优化

**状态**：✅ 已在 v1.6 运行时修复。安装 `mesa-utils dmidecode`。

> `dmidecode` 在容器中无法读取 `/dev/mem`（需要 `SYS_RAWIO` 权限），但安装后警告消失，其余功能正常。

---

#### 建议 10：增加更多中文字体

**现状**：已有 Noto CJK + 文泉驿，可补充更丰富的中文字体。

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-noto-cjk-extra \
    fontconfig \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

可选手动安装：霞鹜文楷（LXGW WenKai）、思源黑体/宋体独立包。

---

#### 建议 11：Chromium 默认搜索引擎改为百度

```json
// 在 Preferences 中添加
{
  "default_search_provider_data": {
    "template_url_data": {
      "short_name": "百度",
      "keyword": "baidu.com",
      "url": "https://www.baidu.com/s?wd={searchTerms}",
      "suggest_url": "https://suggestion.baidu.com/su?wd={searchTerms}&action=opensearch"
    }
  }
}
```

> 也可保持 Google，视用户群体而定。建议至少添加百度为可选搜索引擎。

---

#### 建议 12：增加 Chromium 策略配置

通过 Chromium 策略预配置中国用户友好行为：

```bash
mkdir -p /etc/chromium/policies/managed
cat > /etc/chromium/policies/managed/devtop.json << 'EOF'
{
  "BookmarkBarEnabled": true,
  "RestoreOnStartup": 4,
  "RestoreOnStartupURLs": ["https://www.baidu.com"],
  "DefaultSearchProviderEnabled": true
}
EOF
```

---

#### 建议 13：SSH 服务配置

容器内已安装 openssh-server，但未配置自启动。如需远程 SSH 接入：

```dockerfile
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
```

---

#### 建议 14：镜像体积优化

当前镜像 9.05GB，可优化点：

| 优化项 | 预估节省 | 方法 |
|---|---|---|
| 合并 RUN 层 | ~200MB | 多个 apt-get 合并为一条 RUN |
| 清理 apt 缓存 | ~100MB | 确保每层都 `rm -rf /var/lib/apt/lists/*` |
| 清理 pip 缓存 | ~50MB | `pip cache purge` |
| 清理 npm 缓存 | ~50MB | `npm cache clean --force` |
| 清理 Go 模块缓存 | ~100MB | `go clean -modcache` |
| 移除构建依赖 | ~200MB | 编译完成后移除 build-essential（如不需要） |
| 使用 `--no-install-recommends` | ~300MB | 所有 apt-get install 都加此参数 |

---

## 三、优化迭代方案（分阶段）

### 阶段一：紧急修复（v1.5.1 — 热修复）

**目标**：修复影响中文用户的核心问题，不改变镜像基础结构。

| # | 修复项 | 优先级 | 复杂度 | 状态 |
|---|---|---|---|---|
| 1 | fcitx5 自启动配置 | P0 | 低 | ✅ 已修复 |
| 2 | 创建 webtop-env.md 帮助文档 | P0 | 低 | ✅ 已修复 |
| 3 | APT 换中国镜像 | P0 | 低 | ✅ 已修复 |
| 4 | pip 换中国镜像 | P0 | 低 | ✅ 已修复 |
| 5 | npm 换淘宝镜像 | P0 | 低 | ✅ 已修复 |
| 6 | Go GOPROXY 换 goproxy.cn | P0 | 低 | ✅ 已修复 |
| 7 | Cargo 换中国镜像 | P1 | 低 | ✅ 已修复 |
| 8 | Docker registry mirror | P1 | 低 | ✅ 已修复 |
| 9 | hardinfo2 缺失依赖 (mesa-utils/dmidecode) | P1 | 低 | ✅ 已修复 |

**预估实现**：1-2 小时，可立即提升中国用户体验。

### 阶段二：功能补全（v1.6）

**目标**：补齐日常使用所需的软件和工具。

| # | 新增项 | 说明 |
|---|---|---|
| 1 | ffmpeg + GStreamer 插件 | 媒体播放/转码 |
| 2 | mpv 播放器 | 轻量视频播放 |
| 3 | LibreOffice（中文版） | 办公文档 |
| 4 | aria2 + unrar | 下载/解压 |
| 5 | lazygit + lazydocker | 现代 CLI 工具 |
| 6 | fastfetch | 系统信息展示 |
| 7 | Chromium 书签完善 | 中国常用网站 |
| 8 | Chromium 策略配置 | 预配置友好行为 |

**预估镜像增长**：~800MB（LibreOffice 占主要）。

### 阶段三：体验打磨（v2.0）

**目标**：深度优化中文用户体验和镜像效率。

| # | 优化项 | 说明 |
|---|---|---|
| 1 | 更多中文字体 | LXGW WenKai 等 |
| 2 | 桌面主题优化 | 中文壁纸、图标 |
| 3 | 镜像分层 | base / dev / office 三层 |
| 4 | 镜像瘦身 | 清理缓存、合并层 |
| 5 | 健康检查脚本完善 | 中文输入法状态检测 |
| 6 | 预装中文输入法词典 | 拼音词库增强 |

---

## 四、推荐的 Dockerfile 补丁

以下为可直接使用的 Dockerfile 补丁（基于现有 v1.5）：

```dockerfile
# ========== 阶段一：紧急修复 ==========

# 1. APT 换阿里云镜像
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.aliyun.com/ubuntu/|g' \
        /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's|http://security.ubuntu.com/ubuntu/|https://mirrors.aliyun.com/ubuntu/|g' \
        /etc/apt/sources.list.d/ubuntu.sources

# 2. fcitx5 自启动
RUN cp /usr/share/applications/org.fcitx.Fcitx5.desktop /etc/xdg/autostart/ && \
    sed -i 's/^OnlyShowIn=.*/OnlyShowIn=KDE;XFCE;GNOME/' \
        /etc/xdg/autostart/org.fcitx.Fcitx5.desktop 2>/dev/null || true

# 3. pip 阿里云镜像
RUN mkdir -p /etc && \
    printf '[global]\nindex-url = https://mirrors.aliyun.com/pypi/simple/\ntrusted-host = mirrors.aliyun.com\n' \
    > /etc/pip.conf

# 4. npm 淘宝镜像
RUN npm config set registry https://registry.npmmirror.com

# 5. Go 七牛镜像
RUN go env -w GOPROXY=https://goproxy.cn,direct

# 6. Cargo 上海交大镜像
RUN mkdir -p /usr/local/cargo && \
    printf '[source.crates-io]\nreplace-with = "sjtu"\n[source.sjtu]\nregistry = "sparse+https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/"\n' \
    > /usr/local/cargo/config.toml

# 7. Docker 镜像加速
RUN mkdir -p /etc/docker && \
    printf '{"registry-mirrors":["https://docker.mirrors.sjtug.sjtu.edu.cn","https://docker.mirrors.ustc.edu.cn"]}' \
    > /etc/docker/daemon.json

# 8. 创建中文输入帮助文档
RUN printf '# 中文输入法使用说明\n\n## 快捷键\n- Ctrl+Space: 切换中英文输入\n- Shift: 临时切换英文\n\n## 输入法\n- 默认: 拼音输入法\n- 双拼: 自然码方案\n\n## 排查\n如输入法未启动，终端执行: `fcitx5 -d --replace`\n' \
    > /workspace/webtop-env.md

# ========== 阶段二：功能补全 ==========

# 9. 媒体工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    mpv \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 10. 下载/压缩工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 \
    unrar \
    sshpass \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 11. 现代 CLI 工具
RUN curl -fsSL "$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
    | grep -oP '"browser_download_url": "\K[^"]*Linux_x86_64.tar.gz')" \
    | tar xz -C /usr/local/bin lazygit

# 12. LibreOffice 中文版（可选，+500MB）
RUN apt-get update && apt-get install -y --no-install-recommends \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-l10n-zh-cn \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
```

---

## 五、运行时即时修复脚本

以下脚本可在当前运行的容器中立即执行，无需重建镜像：

```bash
#!/bin/bash
# devtop-hotfix.sh — 在容器内执行，立即修复 P0 问题

echo "===== 1. 修复 fcitx5 自启动 ====="
mkdir -p /config/.config/autostart
cp /usr/share/applications/org.fcitx.Fcitx5.desktop /config/.config/autostart/

echo "===== 2. 创建中文输入帮助文档 ====="
cat > /workspace/webtop-env.md << 'MDEOF'
# 中文输入法使用说明

## 快捷键
- `Ctrl+Space`: 切换中英文输入
- `Shift`: 临时切换英文（在中文模式下）
- `Ctrl+.`: 切换全角/半角标点

## 输入法
- **拼音输入法**: 默认输入法，支持拆字、符号、英文候选词
- **双拼**: 自然码方案（可在 fcitx5 配置中切换）

## 排查
如输入法未启动，终端执行:
```bash
fcitx5 -d --replace
```

## 配置工具
终端执行 `fcitx5-config-qt` 打开图形配置界面。
MDEOF

echo "===== 3. APT 换阿里云镜像 ====="
sed -i 's|http://archive.ubuntu.com/ubuntu/|https://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources
sed -i 's|http://security.ubuntu.com/ubuntu/|https://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

echo "===== 4. pip 换阿里云镜像 ====="
cat > /etc/pip.conf << 'EOF'
[global]
index-url = https://mirrors.aliyun.com/pypi/simple/
trusted-host = mirrors.aliyun.com
EOF

echo "===== 5. npm 换淘宝镜像 ====="
npm config set registry https://registry.npmmirror.com

echo "===== 6. Go 换七牛镜像 ====="
go env -w GOPROXY=https://goproxy.cn,direct

echo "===== 7. Cargo 换上海交大镜像 ====="
mkdir -p /usr/local/cargo
cat > /usr/local/cargo/config.toml << 'EOF'
[source.crates-io]
replace-with = "sjtu"
[source.sjtu]
registry = "sparse+https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/"
EOF

echo "===== 8. Docker 镜像加速 ====="
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{"registry-mirrors":["https://docker.mirrors.sjtug.sjtu.edu.cn","https://docker.mirrors.ustc.edu.cn"]}
EOF

echo "===== 完成！重启容器生效 ====="
echo "执行: docker compose restart webtop"
```

---

## 六、总结评分

| 维度 | 评分 | 说明 |
|---|---|---|
| **开发工具** | ⭐⭐⭐⭐⭐ | 语言全覆盖（Python/Node/Go/Rust/Bun），工具链完整 |
| **中文环境** | ⭐⭐⭐☆☆ | 字体/locale/输入法框架齐全，但**输入法不自启动**是硬伤 |
| **网络速度** | ⭐⭐☆☆☆ | **全链路无中国镜像**，严重影响中国用户体验 |
| **桌面体验** | ⭐⭐⭐⭐☆ | XFCE + Wayland 配置完善，缺媒体播放器和办公软件 |
| **镜像效率** | ⭐⭐⭐☆☆ | 9GB 偏大，有清理和分层优化空间 |
| **综合** | ⭐⭐⭐☆☆ | 基础优秀，但中文用户核心体验有阻断性问题 |

### 一句话总结

> **开发工具链一流，中文基础设施齐全但「最后一公里」未打通**——fcitx5 不自启动 + 全链路无中国镜像，这两个问题修复后即可成为优秀的中文开发者桌面镜像。
