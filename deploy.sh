#!/usr/bin/env bash
# deploy.sh — WorkBuddy-DevTop 一键部署脚本
# 自动生成随机密码，启动容器，输出访问信息
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE=".env"
CUSTOM_USER="${CUSTOM_USER:-admin}"

# ========== 生成随机密码 ==========
generate_password() {
    # 生成 20 位随机密码（字母+数字）
    head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20
}

# ========== 检查/生成 .env ==========
if [ ! -f "$ENV_FILE" ]; then
    PASSWORD=$(generate_password)
    cat > "$ENV_FILE" << EOF
# WorkBuddy-DevTop 自动生成 — 请勿提交到仓库
CUSTOM_USER=${CUSTOM_USER}
PASSWORD=${PASSWORD}
EOF
    chmod 600 "$ENV_FILE"
    echo "[deploy] 已生成 .env 文件，随机密码已设置"
    NEW_DEPLOY=true
else
    # 加载已有密码
    source "$ENV_FILE"
    echo "[deploy] 使用已有 .env 中的密码"
    NEW_DEPLOY=false
fi

# ========== 启动容器 ==========
echo "[deploy] 启动容器..."
docker compose up -d

# ========== 健康检查 ==========
echo "[deploy] 等待服务就绪..."
for i in $(seq 1 12); do
    if curl -sI http://localhost:3000 2>&1 | grep -q "401\|200"; then
        echo "[deploy] ✅ 服务已就绪"
        break
    fi
    echo "[deploy] 等待启动... ($i/12)"
    sleep 5
done

# ========== 生成访问链接 ==========
if [ -n "${X_IDE_SPACE_KEY:-}" ]; then
    ACCESS_URL="https://webview.e2b.${X_IDE_PREVIEW_DOMAIN}/?x-cs-sandbox-id=${X_IDE_SPACE_KEY}&x-cs-sandbox-port=3000"
else
    ACCESS_URL="http://localhost:3000"
fi

# ========== 输出部署信息 ==========
echo ""
echo "================================================"
echo "  ✅ WorkBuddy-DevTop 部署完成！"
echo "================================================"
echo ""
echo "  🔗 访问地址：${ACCESS_URL}"
echo "  🔑 用户名：${CUSTOM_USER}"
echo "  🔑 密码：${PASSWORD}"
echo ""
if [ "$NEW_DEPLOY" = true ]; then
    echo "  ⚠️ 这是随机生成的密码，已保存在 .env 文件中。"
    echo "     如需修改，编辑 .env 后运行: docker compose down && bash deploy.sh"
fi
echo ""
echo "  💡 首次加载约需 10-20 秒，请耐心等待。"
echo "================================================"
echo ""

# 同时写入 deploy-info.txt 供快速查阅
cat > deploy-info.txt << EOF
============================================================
WorkBuddy-DevTop 部署信息
============================================================

🔗 访问地址: ${ACCESS_URL}
🔑 用户名: ${CUSTOM_USER}
🔑 密码: ${PASSWORD}

🐳 容器名: workbuddy-devtop
🐳 镜像: docker.cnb.cool/fuliai/devtop/base:v1.6

🛠️ 常用运维命令:
  cd ${SCRIPT_DIR}
  docker compose ps                          # 查看状态
  docker compose logs -f workbuddy-devtop    # 实时日志
  docker compose restart workbuddy-devtop    # 重启
  docker compose down                        # 停止
  docker compose up -d                       # 启动
  docker exec -it workbuddy-devtop /bin/bash # 进容器 shell

============================================================
EOF
