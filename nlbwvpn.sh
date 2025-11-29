#!/usr/bin/env bash
#
# nlbwvpn - Ultimate VLESS + Socks5 + Monitoring Script
# GitHub Repository: https://github.com/Hupan0210/vpn
# License: MIT
#
# ==============================================================================
# 🌟 FEATURES LIST (功能清单)
# ==============================================================================
# 1. Non-invasive Nginx configuration (Domain specific) - 不破坏现有网站
# 2. Randomized WebSocket path & Socks5 Port - 随机路径抗探测
# 3. Full Lifecycle Management (Menu System) - 全生命周期管理菜单
# 4. Auto-renewal of SSL certificates - 自动续签证书
# 5. Dual Inbound: VLESS (Primary) + Socks5 (Backup) - 双协议支持
# 6. Active Monitoring: Process Health Check + Weekly Reports - 实时监控与周报
# 7. Robust Permission Management - 强健的权限管理
# ==============================================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ==============================================================================
# 🔧 GLOBAL VARIABLES (全局变量)
# ==============================================================================
LOG_FILE="/root/deploy.log"
CONFIG_ENV="/etc/nlbwvpn/config.env"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_LOG_DIR="/var/log/xray"

exec > >(tee -a "$LOG_FILE") 2>&1

# Color helpers
green(){ echo -e "\033[1;32m$1\033[0m"; }
yellow(){ echo -e "\033[1;33m$1\033[0m"; }
red(){ echo -e "\033[1;31m$1\033[0m"; }

# Check Root
if [[ $EUID -ne 0 ]]; then
   red "❌ Error: This script must be run as root."
   exit 1
fi

# ==============================================================================
# 🛠️ HELPER FUNCTIONS (辅助函数库)
# ==============================================================================

# Function: Send Telegram Notification with Retry
send_tg_notify() {
    local text="$1"
    local file="${2:-}"
    
    if [[ -z "${BOT_TOKEN:-}" ]] && [[ -f "$CONFIG_ENV" ]]; then source "$CONFIG_ENV"; fi

    if [[ "${TG_ENABLE:-false}" == "true" ]] && [[ -n "${BOT_TOKEN:-}" ]] && [[ -n "${CHAT_ID:-}" ]]; then
        local api_url="https://api.telegram.org/bot${BOT_TOKEN}"
        # Retry logic: Try 3 times before failing
        for i in {1..3}; do
            curl -s -X POST "${api_url}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$text" >/dev/null && break || sleep 2
        done
        # Send file if exists (e.g., QR Code)
        if [[ -n "$file" ]] && [[ -f "$file" ]]; then
             curl -s -F chat_id="${CHAT_ID}" -F document=@"$file" -F caption="Scan to Import" "${api_url}/sendDocument" >/dev/null || true
        fi
    fi
}

# Function: Fix System Permissions (Critical for Xray)
fix_permissions() {
    # Ensure log directory exists and is writable
    mkdir -p "$XRAY_LOG_DIR"
    touch "$XRAY_LOG_DIR/access.log" "$XRAY_LOG_DIR/error.log"
    chown -R nobody:nogroup "$XRAY_LOG_DIR"
    
    # Ensure config is readable by Xray (running as nobody user)
    if [[ -f "$XRAY_CONF" ]]; then
        chmod 644 "$XRAY_CONF"
        chown nobody:nogroup "$XRAY_CONF"
    fi
}

# Function: Modify Socks5 Settings
modify_socks5() {
    green "🛠️ 修改 Socks5 配置"
    local new_port=$(shuf -i 20000-50000 -n 1)
    local new_user="u$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
    local new_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

    echo "您可以输入自定义信息，或者直接回车使用随机生成的默认值。"
    read -r -p "新端口 [默认: ${new_port}]: " input_port
    read -r -p "新用户名 [默认: ${new_user}]: " input_user
    read -r -p "新密码 [默认: ${new_pass}]: " input_pass

    SOCKS_PORT=${input_port:-$new_port}
    SOCKS_USER=${input_user:-$new_user}
    SOCKS_PASS=${input_pass:-$new_pass}

    if [[ -f "$XRAY_CONF" ]]; then
        local tmp_json=$(mktemp)
        # Use jq to safely edit JSON without breaking syntax
        jq --argjson port "$SOCKS_PORT" --arg user "$SOCKS_USER" --arg pass "$SOCKS_PASS" \
           '(.inbounds[] | select(.protocol=="socks")) |= (.port = $port | .settings.accounts[0].user = $user | .settings.accounts[0].pass = $pass)' \
           "$XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$XRAY_CONF"
        
        # CRITICAL FIX: Re-apply permissions after file modification
        fix_permissions
        
        green "🔄 重启 Xray 服务..."
        systemctl restart xray
        
        if [[ -f "$CONFIG_ENV" ]]; then source "$CONFIG_ENV"; fi
        local domain_safe=$(echo "${DOMAIN:-Unknown}" | sed 's/[.!]/\\&/g')
        local link="socks5://${SOCKS_USER}:${SOCKS_PASS}@${DOMAIN}:${SOCKS_PORT}#${DOMAIN}-socks"
        local link_safe=$(echo "$link" | sed 's/[][_*`~()<>#+=\-|{}.!]/\\&/g')
        local msg="🛠️ *Socks5 Config Updated*\n\nDomain: \`${domain_safe}\`\nPort: \`${SOCKS_PORT}\`\nLink: \`${link_safe}\`"
        send_tg_notify "$msg"
        green "✅ 修改成功！新配置已发送至 Telegram。"
        echo "Socks5 Link: $link"
    else
        red "❌ 错误: 未找到 Xray 配置文件。"
    fi
}

# Function: Show Current Config
show_info() {
    if [[ -f "$XRAY_CONF" ]]; then
        green "📊 当前配置信息"
        local socks_port=$(jq -r '.inbounds[] | select(.protocol=="socks") | .port' "$XRAY_CONF")
        local socks_user=$(jq -r '.inbounds[] | select(.protocol=="socks") | .settings.accounts[0].user' "$XRAY_CONF")
        local socks_pass=$(jq -r '.inbounds[] | select(.protocol=="socks") | .settings.accounts[0].pass' "$XRAY_CONF")
        local uuid=$(jq -r '.inbounds[] | select(.protocol=="vless") | .settings.clients[0].id' "$XRAY_CONF")
        local path=$(jq -r '.inbounds[] | select(.protocol=="vless") | .streamSettings.wsSettings.path' "$XRAY_CONF")
        if [[ -f "$CONFIG_ENV" ]]; then source "$CONFIG_ENV"; fi
        echo "域名: ${DOMAIN:-Unknown}"
        echo "UUID: $uuid"
        echo "路径: $path"
        echo "Socks5: $socks_port ($socks_user / $socks_pass)"
    else
        red "❌ 未找到配置文件"
    fi
}

# Function: Management Menu
management_menu() {
    clear
    green "🚀 nlbwvpn 管理面板"
    if [[ -f "$CONFIG_ENV" ]]; then source "$CONFIG_ENV"; echo "当前域名: ${DOMAIN:-Unknown}"; fi
    echo "------------------------------------------------"
    echo "1. 🛠️  修改 Socks5 端口/密码"
    echo "2. 📊  查看当前配置"
    echo "3. 🔄  强制重新安装"
    echo "0. 🚪  退出"
    echo "------------------------------------------------"
    read -r -p "请选择 [0-3]: " choice
    case "$choice" in
        1) modify_socks5 ;;
        2) show_info ;;
        3) return 0 ;;
        0) exit 0 ;;
        *) red "无效选择"; exit 1 ;;
    esac
    exit 0
}

# Auto-launch menu if installed
if [[ -f "$CONFIG_ENV" ]]; then management_menu; fi

# ==============================================================================
# 🚀 INSTALLATION LOGIC STARTS HERE (安装流程)
# ==============================================================================

green "🚀 Starting New Deployment..."

# 1. Inputs & Interactions
while true; do
    read -r -p "请输入您的域名 (例如 vpn.example.com): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then break; fi; red "域名不能为空"
done

while true; do
    read -r -p "请输入证书邮箱 (例如 admin@example.com): " EMAIL
    if [[ -n "$EMAIL" ]]; then break; fi; red "邮箱不能为空"
done

yellow "🤖 是否配置 Telegram 机器人? [y/N]"
read -r TG_CHOICE
TG_ENABLE=false
BOT_TOKEN=""
CHAT_ID=""
if [[ "$TG_CHOICE" =~ ^[Yy]$ ]]; then
    read -r -p "Telegram Bot Token: " BOT_TOKEN
    read -r -p "Telegram Chat ID: " CHAT_ID
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then TG_ENABLE=true; else yellow "信息为空，跳过 Telegram 配置。"; fi
fi

# 2. Generate Random Credentials
RAND_PATH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 6)
WS_PATH="/${RAND_PATH}"
UUID="$(cat /proc/sys/kernel/random/uuid)"
SOCKS_PORT=$(shuf -i 20000-50000 -n 1)
SOCKS_USER="u$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
SOCKS_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

echo ""
green "📝 配置确认: $DOMAIN | $EMAIL | Socks5 Port: $SOCKS_PORT"
echo ""

# 3. System Dependencies
green "📦 安装系统依赖..."
apt-get update -y
apt-get install -y curl jq bc nginx certbot python3-certbot-nginx unzip openssl qrencode git socat

# 4. Install Xray Core
if ! command -v xray &> /dev/null; then
    green "⬇️ 安装 Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# 5. Configure Nginx (Web Server)
green "🌐 配置 Nginx..."
WEB_ROOT="/var/www/${DOMAIN}/html"
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
mkdir -p "$WEB_ROOT"
if [[ ! -f "$WEB_ROOT/index.html" ]]; then
    cat > "$WEB_ROOT/index.html" <<EOF
<!DOCTYPE html><html><head><title>Welcome</title></head><body><h1>Welcome to nginx!</h1></body></html>
EOF
fi
chown -R www-data:www-data "/var/www/${DOMAIN}"
chmod -R 755 "/var/www/${DOMAIN}"

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${WEB_ROOT};
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
systemctl restart nginx

# 6. Apply SSL Certificate
green "🔒 申请 SSL 证书..."
if certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect; then
    green "✅ 证书申请成功"
else
    red "❌ 证书申请失败，尝试 webroot 模式..."
    certbot certonly --webroot -w "$WEB_ROOT" -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive || { red "❌ 最终失败"; exit 1; }
fi

# 7. Write Final Configuration
green "🔧 写入最终配置..."
cat > "$XRAY_CONF" <<EOF
{
  "log": { "loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log" },
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [{ "id": "${UUID}", "level": 0 }], "decryption": "none" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${WS_PATH}" } }
    },
    {
      "port": ${SOCKS_PORT},
      "protocol": "socks",
      "settings": { "auth": "password", "accounts": [{ "user": "${SOCKS_USER}", "pass": "${SOCKS_PASS}" }], "udp": true }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# CRITICAL: Fix permissions on install
fix_permissions
systemctl restart xray

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    root ${WEB_ROOT};
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
    location ${WS_PATH} {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
systemctl restart nginx

# 8. Network Optimization (BBR)
green "🚀 优化网络 (BBR)..."
if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
    cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p
fi

# 9. Save Config & Generate Links
mkdir -p /etc/nlbwvpn
cat > "$CONFIG_ENV" <<EOF
DOMAIN="${DOMAIN}"
TG_ENABLE="${TG_ENABLE}"
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
EOF

VLESS_LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${WS_PATH}#${DOMAIN}"
SOCKS_LINK="socks5://${SOCKS_USER}:${SOCKS_PASS}@${DOMAIN}:${SOCKS_PORT}#${DOMAIN}-socks"
qrencode -o /root/vless-qrcode.png "$VLESS_LINK"

# ==============================================================================
# 10. Install Monitoring Services (监控系统)
# ==============================================================================
if [[ "${TG_ENABLE}" == "true" ]]; then
    green "⏱️ 安装监控服务..."
    
    # Script 1: Health Monitor (5min check)
    cat > /usr/local/bin/nlbw-monitor.sh <<'EOF_MON'
#!/bin/bash
source /etc/nlbwvpn/config.env
API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
send_alert() {
    curl -s -X POST "${API_URL}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$(echo "$1" | sed 's/[.!]/\\&/g')" >/dev/null
}
for svc in xray nginx; do
    if ! systemctl is-active --quiet "$svc"; then
        systemctl restart "$svc"
        send_alert "⚠️ Alert: Service ${svc} restarted on $(hostname)."
    fi
done
EOF_MON
    chmod +x /usr/local/bin/nlbw-monitor.sh
    
    # Systemd: Monitor
    cat > /etc/systemd/system/nlbw-monitor.service <<EOF_SVC
[Unit]
Description=VPN Health Monitor
[Service]
Type=oneshot
ExecStart=/usr/local/bin/nlbw-monitor.sh
EOF_SVC
    cat > /etc/systemd/system/nlbw-monitor.timer <<EOF_TMR
[Unit]
Description=Run VPN Health Monitor every 5 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF_TMR
    
    # Script 2: Weekly Report
    cat > /usr/local/bin/nlbw-weekly.sh <<'EOF_WEEK'
#!/bin/bash
source /etc/nlbwvpn/config.env
API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
if [[ -f "$CERT_FILE" ]]; then EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2); else EXPIRY="Unknown"; fi
MSG="📊 *Weekly Report*\nDomain: ${DOMAIN}\nUptime: $(uptime -p)\nSSL Expiry: ${EXPIRY}"
curl -s -X POST "${API_URL}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$(echo "$MSG" | sed 's/[.!]/\\&/g')" >/dev/null
EOF_WEEK
    chmod +x /usr/local/bin/nlbw-weekly.sh
    
    # Systemd: Weekly
    cat > /etc/systemd/system/nlbw-weekly.service <<EOF_WSVC
[Unit]
Description=VPN Weekly Report
[Service]
Type=oneshot
ExecStart=/usr/local/bin/nlbw-weekly.sh
EOF_WSVC
    cat > /etc/systemd/system/nlbw-weekly.timer <<EOF_WTMR
[Unit]
Description=Timer for VPN Weekly Report
[Timer]
OnCalendar=Mon 09:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF_WTMR
    
    # Enable Timers
    systemctl daemon-reload
    systemctl enable --now nlbw-monitor.timer
    systemctl enable --now nlbw-weekly.timer
    
    # Final Notification
    ESC_DOMAIN=$(echo "$DOMAIN" | sed 's/[.!]/\\&/g')
    ESC_VLESS=$(echo "$VLESS_LINK" | sed 's/[][_*`~()<>#+=\-|{}.!]/\\&/g')
    ESC_SOCKS=$(echo "$SOCKS_LINK" | sed 's/[][_*`~()<>#+=\-|{}.!]/\\&/g')
    TEXT="✅ *Deployment Successful*\n\nDomain: \`${ESC_DOMAIN}\`\n\n*VLESS:*\n\`${ESC_VLESS}\`\n\n*Socks5:*\nLink: \`${ESC_SOCKS}\`"
    send_tg_notify "$TEXT" "/root/vless-qrcode.png"
fi

green "🎉 全部完成! VLESS: $VLESS_LINK"
echo "Socks5: $SOCKS_LINK"
