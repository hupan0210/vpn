#!/usr/bin/env bash
#
# nlbwvpn - Ultimate VLESS + Socks5 + Monitoring Script
# GitHub Repository: https://github.com/Hupan0210/vpn
# License: MIT
#
# Features:
# 1. Non-invasive Nginx configuration (Domain specific).
# 2. Randomized WebSocket path & Socks5 Port for security.
# 3. Full Lifecycle Management (Menu System).
# 4. Auto-renewal of SSL certificates.
# 5. Dual Inbound: VLESS (Primary) + Socks5 (Backup).
# 6. Active Monitoring: Process Health Check + Weekly Reports via Telegram.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Global Paths
LOG_FILE="/root/deploy.log"
CONFIG_ENV="/etc/nlbwvpn/config.env"
XRAY_CONF="/usr/local/etc/xray/config.json"

exec > >(tee -a "$LOG_FILE") 2>&1

# Color helpers
green(){ echo -e "\033[1;32m$1\033[0m"; }
yellow(){ echo -e "\033[1;33m$1\033[0m"; }
red(){ echo -e "\033[1;31m$1\033[0m"; }
blue(){ echo -e "\033[1;34m$1\033[0m"; }

# Check Root
if [[ $EUID -ne 0 ]]; then
   red "❌ Error: This script must be run as root."
   exit 1
fi

# ==========================================
# 0. Helper Functions & Management
# ==========================================

# Send Telegram Notification Wrapper
send_tg_notify() {
    local text="$1"
    local file="${2:-}"
    
    # Load config if variables are empty
    if [[ -z "${BOT_TOKEN:-}" ]] && [[ -f "$CONFIG_ENV" ]]; then
        source "$CONFIG_ENV"
    fi

    if [[ "${TG_ENABLE:-false}" == "true" ]] && [[ -n "${BOT_TOKEN:-}" ]] && [[ -n "${CHAT_ID:-}" ]]; then
        local api_url="https://api.telegram.org/bot${BOT_TOKEN}"
        # Retry logic for curl
        for i in {1..3}; do
            curl -s -X POST "${api_url}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$text" >/dev/null && break || sleep 2
        done
        
        if [[ -n "$file" ]] && [[ -f "$file" ]]; then
             curl -s -F chat_id="${CHAT_ID}" -F document=@"$file" -F caption="Scan to Import" "${api_url}/sendDocument" >/dev/null || true
        fi
    fi
}

modify_socks5() {
    green "🛠️ 修改 Socks5 配置"
    
    # Generate new random defaults
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

    # Use jq to update config safely
    if [[ -f "$XRAY_CONF" ]]; then
        # Temporary file for jq output
        local tmp_json=$(mktemp)
        jq --argjson port "$SOCKS_PORT" --arg user "$SOCKS_USER" --arg pass "$SOCKS_PASS" \
           '(.inbounds[] | select(.protocol=="socks")) |= (.port = $port | .settings.accounts[0].user = $user | .settings.accounts[0].pass = $pass)' \
           "$XRAY_CONF" > "$tmp_json" && mv "$tmp_json" "$XRAY_CONF"
        
        green "🔄 重启 Xray 服务..."
        systemctl restart xray
        
        # Prepare Notification
        if [[ -f "$CONFIG_ENV" ]]; then source "$CONFIG_ENV"; fi
        local domain_safe=$(echo "${DOMAIN:-Unknown}" | sed 's/[.!]/\\&/g')
        local user_safe=$(echo "$SOCKS_USER" | sed 's/[.!]/\\&/g')
        local pass_safe=$(echo "$SOCKS_PASS" | sed 's/[.!]/\\&/g')
        local link="socks5://${SOCKS_USER}:${SOCKS_PASS}@${DOMAIN}:${SOCKS_PORT}#${DOMAIN}-socks"
        local link_safe=$(echo "$link" | sed 's/[][_*`~()<>#+=\-|{}.!]/\\&/g')

        local msg="🛠️ *Socks5 Config Updated*\n\nDomain: \`${domain_safe}\`\nPort: \`${SOCKS_PORT}\`\nUser: \`${user_safe}\`\nPass: \`${pass_safe}\`\nLink: \`${link_safe}\`"
        
        send_tg_notify "$msg"
        
        green "✅ 修改成功！新配置已发送至 Telegram (如果启用)。"
        echo "Socks5 Link: $link"
    else
        red "❌ 错误: 未找到 Xray 配置文件。"
    fi
}

show_info() {
    if [[ -f "$XRAY_CONF" ]]; then
        green "📊 当前配置信息"
        # Extract info using jq
        local socks_port=$(jq -r '.inbounds[] | select(.protocol=="socks") | .port' "$XRAY_CONF")
        local socks_user=$(jq -r '.inbounds[] | select(.protocol=="socks") | .settings.accounts[0].user' "$XRAY_CONF")
        local socks_pass=$(jq -r '.inbounds[] | select(.protocol=="socks") | .settings.accounts[0].pass' "$XRAY_CONF")
        local uuid=$(jq -r '.inbounds[] | select(.protocol=="vless") | .settings.clients[0].id' "$XRAY_CONF")
        local path=$(jq -r '.inbounds[] | select(.protocol=="vless") | .streamSettings.wsSettings.path' "$XRAY_CONF")
        
        # Load domain
        if [[ -f "$CONFIG_ENV" ]]; then source "$CONFIG_ENV"; fi
        local domain=${DOMAIN:-Unknown}

        echo "------------------------------------------------"
        echo "域名: $domain"
        echo "UUID: $uuid"
        echo "路径: $path"
        echo "------------------------------------------------"
        echo "Socks5 端口: $socks_port"
        echo "Socks5 用户: $socks_user"
        echo "Socks5 密码: $socks_pass"
        echo "------------------------------------------------"
    else
        red "❌ 未找到配置文件"
    fi
}

management_menu() {
    clear
    green "🚀 nlbwvpn 管理面板"
    if [[ -f "$CONFIG_ENV" ]]; then source "$CONFIG_ENV"; echo "当前域名: ${DOMAIN:-Unknown}"; fi
    echo "------------------------------------------------"
    echo "1. 🛠️  修改 Socks5 端口/密码 (Modify Socks5)"
    echo "2. 📊  查看当前配置 (Show Config)"
    echo "3. 🔄  强制重新安装 (Re-install)"
    echo "0. 🚪  退出 (Exit)"
    echo "------------------------------------------------"
    read -r -p "请选择 [0-3]: " choice
    case "$choice" in
        1) modify_socks5 ;;
        2) show_info ;;
        3) return 0 ;; # Proceed to install script
        0) exit 0 ;;
        *) red "无效选择"; exit 1 ;;
    esac
    exit 0
}

# Check if installed (Config env exists)
if [[ -f "$CONFIG_ENV" ]]; then
    management_menu
fi

# ==========================================
# 1. New Installation Logic
# ==========================================

green "🚀 Starting New Deployment..."

# 1.1 Domain
while true; do
    read -r -p "请输入您的域名 (例如 vpn.example.com): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then break; fi
    red "域名不能为空"
done

# 1.2 Email (for Certbot)
while true; do
    read -r -p "请输入用于申请证书的邮箱 (例如 admin@example.com): " EMAIL
    if [[ -n "$EMAIL" ]]; then break; fi
    red "邮箱不能为空"
done

# 1.3 Telegram (Optional)
yellow "🤖 是否配置 Telegram 机器人进行监控和通知? [y/N]"
read -r TG_CHOICE
TG_ENABLE=false
BOT_TOKEN=""
CHAT_ID=""

if [[ "$TG_CHOICE" =~ ^[Yy]$ ]]; then
    read -r -p "Telegram Bot Token: " BOT_TOKEN
    read -r -p "Telegram Chat ID: " CHAT_ID
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        TG_ENABLE=true
    else
        yellow "⚠️ Token 或 Chat ID 为空，已跳过 Telegram 配置。"
    fi
fi

# 1.4 Random Path & Configs
RAND_PATH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 6)
WS_PATH="/${RAND_PATH}"
UUID="$(cat /proc/sys/kernel/random/uuid)"
SOCKS_PORT=$(shuf -i 20000-50000 -n 1)
SOCKS_USER="u$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
SOCKS_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)

echo ""
green "📝 配置确认:"
echo "------------------------------------------------"
echo "域名: $DOMAIN"
echo "Socks5: $SOCKS_PORT"
echo "------------------------------------------------"
echo ""

# ==========================================
# 2. System Preparation
# ==========================================
green "📦 安装系统依赖..."
apt-get update -y
apt-get install -y curl jq bc nginx certbot python3-certbot-nginx unzip openssl qrencode git socat

# ==========================================
# 3. Install Xray
# ==========================================
if ! command -v xray &> /dev/null; then
    green "⬇️ 安装 Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
else
    green "✅ Xray 已安装，跳过."
fi

# ==========================================
# 4. Web Server (Nginx)
# ==========================================
green "🌐 配置 Nginx..."
WEB_ROOT="/var/www/${DOMAIN}/html"
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"

mkdir -p "$WEB_ROOT"
if [[ ! -f "$WEB_ROOT/index.html" ]]; then
    cat > "$WEB_ROOT/index.html" <<EOF
<!DOCTYPE html>
<html><head><title>Welcome</title></head><body><h1>Welcome to nginx!</h1></body></html>
EOF
fi
chown -R www-data:www-data "/var/www/${DOMAIN}"
chmod -R 755 "/var/www/${DOMAIN}"

# Initial Nginx
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

# ==========================================
# 5. SSL Certificate
# ==========================================
green "🔒 申请 SSL 证书..."
if certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect; then
    green "✅ 证书申请成功"
else
    red "❌ 证书申请失败，尝试 webroot 模式..."
    certbot certonly --webroot -w "$WEB_ROOT" -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive || { red "❌ 最终失败"; exit 1; }
fi

# ==========================================
# 6. Final Config
# ==========================================
green "🔧 写入最终配置..."

# 6.1 Xray Config
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

mkdir -p /var/log/xray && chown -R nobody:nogroup /var/log/xray
systemctl restart xray

# 6.2 Nginx Config
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

# ==========================================
# 7. BBR
# ==========================================
green "🚀 优化网络 (BBR)..."
if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
    cat >> /etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p
fi

# ==========================================
# 8. Persistence & Full Monitoring Services
# ==========================================

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

# Install Monitoring Services (Restored Feature)
if [[ "${TG_ENABLE}" == "true" ]]; then
    green "⏱️ 安装监控服务 (Health Monitor & Weekly Report)..."
    
    # A. Health Monitor Script
    cat > /usr/local/bin/nlbw-monitor.sh <<'EOF_MON'
#!/bin/bash
source /etc/nlbwvpn/config.env

API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
send_alert() {
    local msg="$1"
    local esc_msg=$(echo "$msg" | sed 's/[.!]/\\&/g')
    curl -s -X POST "${API_URL}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$esc_msg" >/dev/null
}

# Check Services
for svc in xray nginx; do
    if ! systemctl is-active --quiet "$svc"; then
        systemctl restart "$svc"
        send_alert "⚠️ Alert: Service ${svc} was down and has been restarted on $(hostname)."
    fi
done
EOF_MON
    chmod +x /usr/local/bin/nlbw-monitor.sh

    # B. Health Monitor Timer (Run every 5 mins)
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

    # C. Weekly Report Script
    cat > /usr/local/bin/nlbw-weekly.sh <<'EOF_WEEK'
#!/bin/bash
source /etc/nlbwvpn/config.env
API_URL="https://api.telegram.org/bot${BOT_TOKEN}"

# Cert Expiry
CERT_FILE="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
if [[ -f "$CERT_FILE" ]]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
else
    EXPIRY="Unknown"
fi

# Load & Uptime
LOAD=$(uptime | awk -F'load average:' '{ print $2 }')
UPTIME=$(uptime -p)

# Send
MSG="📊 *Weekly Report*\nHost: $(hostname)\nDomain: ${DOMAIN}\nUptime: ${UPTIME}\nLoad: ${LOAD}\nSSL Expiry: ${EXPIRY}"
ESC_MSG=$(echo "$MSG" | sed 's/[.!]/\\&/g') # Basic escape

curl -s -X POST "${API_URL}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$ESC_MSG" >/dev/null
EOF_WEEK
    chmod +x /usr/local/bin/nlbw-weekly.sh

    # D. Weekly Report Timer (Run every Monday)
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

    # Enable all
    systemctl daemon-reload
    systemctl enable --now nlbw-monitor.timer
    systemctl enable --now nlbw-weekly.timer
fi

green "✅ 部署完成!"
echo "VLESS: $VLESS_LINK"
echo "Socks5: $SOCKS_LINK"

# Notification
if $TG_ENABLE; then
    green "🤖 发送 Telegram 通知..."
    
    ESC_DOMAIN=$(echo "$DOMAIN" | sed 's/[.!]/\\&/g')
    ESC_VLESS=$(echo "$VLESS_LINK" | sed 's/[][_*`~()<>#+=\-|{}.!]/\\&/g')
    ESC_SOCKS=$(echo "$SOCKS_LINK" | sed 's/[][_*`~()<>#+=\-|{}.!]/\\&/g')
    ESC_SUSER=$(echo "$SOCKS_USER" | sed 's/[.!]/\\&/g')
    ESC_SPASS=$(echo "$SOCKS_PASS" | sed 's/[.!]/\\&/g')
    
    TEXT="✅ *Deployment Successful*\n\nDomain: \`${ESC_DOMAIN}\`\n\n*VLESS:*\n\`${ESC_VLESS}\`\n\n*Socks5:*\nUser: \`${ESC_SUSER}\`\nPass: \`${ESC_SPASS}\`\nLink: \`${ESC_SOCKS}\`"
    
    send_tg_notify "$TEXT" "/root/vless-qrcode.png"
fi

green "🎉 全部完成! 再次运行此脚本可进入管理面板修改配置。"
