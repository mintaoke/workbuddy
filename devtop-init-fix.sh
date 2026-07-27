#!/usr/bin/with-contenv bash
# devtop-init-fix.sh
# CloudStudio 沙箱环境兼容修复脚本
# 通过 linuxserver /custom-cont-init.d/ 机制在容器每次启动时自动执行
# 在其他平台运行为 no-op，不影响正常行为

set -e

echo "[devtop-init-fix] 开始环境兼容修复..."

# ========== 修复 1: dockremap 用户名冲突 ==========
# CloudStudio 宿主启用了 Docker userns-remap，会在容器 /etc/passwd 注入
# dockremap:x:1000:1000，与镜像的 aican.do:x:1000:1000 冲突，
# 导致 ls 等命令显示属主为 dockremap 而非 aican.do。
# 其他平台无此问题，此操作为 no-op。

if grep -q "^dockremap:x:1000:" /etc/passwd 2>/dev/null; then
    echo "[devtop-init-fix] 检测到 dockremap 用户冲突，移除..."
    sed -i '/^dockremap:x:1000:/d' /etc/passwd
    sed -i '/^dockremap:x:1000:/d' /etc/group
    echo "[devtop-init-fix] dockremap 已移除，aican.do 现在是唯一的 uid=1000 用户"
fi

# ========== 修复 2: .zshrc 和 oh-my-zsh 初始化 ==========
# 在某些环境下（如 /config 首次挂载空目录），zsh 可能在默认配置复制完成前
# 首次启动，自动生成空的 .zshrc（仅含 "# Created by newuser"），
# 覆盖了镜像应有的完整配置。

ZSHRC_FILE="/config/.zshrc"
DEFAULT_ZSHRC="/defaults/devtop-config/.zshrc"

# 检查 .zshrc 是否缺失或为空壳（少于 10 行说明是 newuser 自动生成的）
if [ ! -f "$ZSHRC_FILE" ] || [ "$(wc -l < "$ZSHRC_FILE")" -lt 10 ]; then
    echo "[devtop-init-fix] .zshrc 缺失或不完整，从默认配置恢复..."
    if [ -f "$DEFAULT_ZSHRC" ]; then
        cp "$DEFAULT_ZSHRC" "$ZSHRC_FILE"
        chown 1000:1000 "$ZSHRC_FILE"
        echo "[devtop-init-fix] .zshrc 已恢复 ($(wc -l < "$ZSHRC_FILE") 行)"
    fi
fi

# 检查 oh-my-zsh 是否存在
if [ ! -d "/config/.oh-my-zsh" ]; then
    echo "[devtop-init-fix] oh-my-zsh 缺失，从 root 复制..."
    if [ -d "/root/.oh-my-zsh" ]; then
        cp -a /root/.oh-my-zsh /config/.oh-my-zsh
        mkdir -p /config/.oh-my-zsh/completions
        chown -R 1000:1000 /config/.oh-my-zsh
        echo "[devtop-init-fix] oh-my-zsh 已复制到 /config/"
    fi
fi

# 确保 completions 目录存在
mkdir -p /config/.oh-my-zsh/completions 2>/dev/null || true
chown -R 1000:1000 /config/.oh-my-zsh 2>/dev/null || true

# ========== 修复 3: hardinfo2 缺失依赖安装 ==========
# hardinfo2（硬件信息）依赖 mesa-utils（glxinfo）和 dmidecode 来获取完整系统信息。
# 镜像未预装这些可选依赖，导致 GUI 弹出"未正确打包"警告。
# 注意：dmidecode 在容器中因无法访问 /dev/mem 而无法读取 DMI 数据，
# 但安装后警告消失，hardinfo2 可正常使用其他所有功能。

if ! dpkg -s mesa-utils dmidecode >/dev/null 2>&1; then
    echo "[devtop-init-fix] 安装 hardinfo2 缺失依赖: mesa-utils dmidecode..."
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq mesa-utils dmidecode 2>/dev/null
    echo "[devtop-init-fix] hardinfo2 依赖已安装"
fi

# ========== 修复 4: fcitx5 自启动（保险措施） ==========
# 确保中文输入法自启动配置存在
if [ ! -f "/config/.config/autostart/org.fcitx.Fcitx5.desktop" ]; then
    echo "[devtop-init-fix] fcitx5 自启动缺失，配置中..."
    mkdir -p /config/.config/autostart
    if [ -f "/usr/share/applications/org.fcitx.Fcitx5.desktop" ]; then
        cp /usr/share/applications/org.fcitx.Fcitx5.desktop /config/.config/autostart/
        chown -R 1000:1000 /config/.config/autostart
        echo "[devtop-init-fix] fcitx5 自启动已配置"
    fi
fi

# ========== 修复 5: VS Code 桌面版安装与桌面快捷方式 ==========
# 安装 Microsoft 官方 VS Code 桌面版（非 code-server Web 版）
# 并在桌面上创建启动图标，用户双击即可使用

echo "[devtop-init-fix] 检查 VS Code 桌面版..."

if ! command -v code &>/dev/null; then
    echo "[devtop-init-fix] VS Code 未安装，正在安装桌面版..."
    # 安装依赖
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq wget gpg 2>/dev/null

    # 添加 Microsoft APT 源
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.gpg
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" \
        > /etc/apt/sources.list.d/vscode.list

    # 安装 VS Code
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq code 2>/dev/null
    echo "[devtop-init-fix] VS Code 桌面版安装完成"
else
    CODE_VERSION=$(code --version 2>&1 | head -1 || echo "未知")
    echo "[devtop-init-fix] VS Code 桌面版已安装: ${CODE_VERSION}"
fi

# 确保桌面目录存在
mkdir -p /config/Desktop

# 创建 VS Code 桌面快捷方式
DESKTOP_SHORTCUT="/config/Desktop/code.desktop"
if [ ! -f "$DESKTOP_SHORTCUT" ]; then
    echo "[devtop-init-fix] 创建 VS Code 桌面快捷方式..."
    cat > "$DESKTOP_SHORTCUT" << 'DESKTOP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Visual Studio Code
Comment=Code Editing. Redefined.
Icon=code
Exec=/usr/share/code/code --no-sandbox --unity-launch %F
Terminal=false
StartupNotify=true
Categories=Development;IDE;TextEditor;
MimeType=text/plain;inode/directory;text/x-code-workspace;
Keywords=vscode;
DESKTOP_EOF
    chown 1000:1000 "$DESKTOP_SHORTCUT"
    chmod +x "$DESKTOP_SHORTCUT"
    echo "[devtop-init-fix] VS Code 桌面快捷方式已创建"
fi

echo "[devtop-init-fix] VS Code 桌面版配置完成。"

# ========== 修复 6: Claude Code (claude) 安装 ==========
# 安装 Anthropic 官方 Claude Code CLI 工具

echo "[devtop-init-fix] 检查 Claude Code..."

if ! command -v claude &>/dev/null; then
    echo "[devtop-init-fix] Claude Code 未安装，正在安装..."
    curl -fsSL https://claude.ai/install.sh | bash
    echo "[devtop-init-fix] Claude Code 安装完成"
else
    CLAUDE_VERSION=$(claude --version 2>&1 | head -1 || echo "未知")
    echo "[devtop-init-fix] Claude Code 已安装: ${CLAUDE_VERSION}"
fi

# ========== 修复 7: SSH 服务配置 ==========
# 配置 SSH 以支持 FinalShell / 终端连接
echo "[devtop-init-fix] 配置 SSH 服务..."

# 安装 openssh-server（如未安装）
if ! command -v sshd &>/dev/null; then
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq openssh-server 2>/dev/null
fi

# 生成 host keys（如缺失）
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A 2>/dev/null || true
fi

# 写入 SSH 配置
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-devtop.conf << 'SSH_EOF'
Port 2222
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
AllowTcpForwarding yes
GatewayPorts yes
ClientAliveInterval 60
ClientAliveCountMax 3
SSH_EOF

# 确保 root 和桌面用户有密码（SSH 密码与桌面密码一致）
SSH_PASSWORD="${PASSWORD:-admin}"
echo "root:${SSH_PASSWORD}" | chpasswd 2>/dev/null || true
echo "aican.do:${SSH_PASSWORD}" | chpasswd 2>/dev/null || true

# 启动 SSH 服务
mkdir -p /run/sshd
if ! pgrep -x sshd >/dev/null 2>&1; then
    /usr/sbin/sshd -p 2222
    echo "[devtop-init-fix] SSH 服务已启动 (端口 2222)"
else
    echo "[devtop-init-fix] SSH 服务已在运行"
fi

# ========== 修复 8: Angular CLI / yargs ESM 兼容 ==========
# yargs v18 是纯 ESM 模块，Angular CLI 用 CJS require() 会导致 ERR_REQUIRE_ESM
# 创建 CJS 桥接文件修复
YARGS_HELPERS_DIR="/root/.nvm/versions/node/v22.13.1/lib/node_modules/@angular/cli/node_modules/yargs/helpers"
if [ -d "$YARGS_HELPERS_DIR" ] && [ ! -f "${YARGS_HELPERS_DIR}/index.js" ]; then
    cat > "${YARGS_HELPERS_DIR}/index.js" << 'CJS_BRIDGE'
// CJS bridge for yargs/helpers (yargs v18 is ESM-only)
module.exports = require('./helpers.mjs');
CJS_BRIDGE
    echo "[devtop-init-fix] Angular CLI yargs ESM 桥接已创建"
fi

echo "[devtop-init-fix] 修复完成。"
