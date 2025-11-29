#!/usr/bin/env bash
#
# nlbwvpn - Automated VLESS-WS-TLS Deployment Script
# GitHub Repository: https://github.com/Hupan0210/vpn
# License: MIT
#
# Features:
# 1. Non-invasive Nginx configuration (Domain specific).
# 2. Randomized WebSocket path for security.
# 3. Optional Telegram notifications & monitoring.
# 4. Auto-renewal of SSL certificates.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Log file
LOG_FILE="/root/deploy.log"
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

green "🚀 Starting Deployment..."

# ==========================================
# 1. Configuration & Interaction
# ==========================================

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

# 1.4 Random Path Generation
# Generate a random 6-character alphanumeric string for the WebSocket path
RAND_PATH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 6)
WS_PATH="/${RAND_PATH}"
UUID="$(cat /proc/sys/kernel/random/uuid)"

echo ""
green "📝 配置确认:"
echo "------------------------------------------------"
echo "域名: $DOMAIN"
echo "邮箱: $EMAIL"
echo "路径: $WS_PATH (随机生成)"
echo "Telegram: $(if $TG_ENABLE; then echo "✅ 启用"; else echo "❌ 禁用"; fi)"
echo "------------------------------------------------"
echo ""

# ==========================================
# 2. System Preparation
# ==========================================
green "📦 安装系统依赖..."
apt-get update -y
apt-get install -y curl jq bc nginx certbot python3-certbot-nginx unzip openssl qrencode git socat

# ==========================================
# 3. Install Xray (Official Script)
# ==========================================
if ! command -v xray &> /dev/null; then
    green "⬇️ 安装 Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
else
    green "✅ Xray 已安装，跳过."
fi

# ==========================================
# 4. Web Server & Camouflage (Non-invasive)
# ==========================================
green "🌐 配置 Nginx..."

WEB_ROOT="/var/www/${DOMAIN}/html"
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"

# Create web root if not exists
mkdir -p "$WEB_ROOT"

# Check if index.html exists. If NOT, create a dummy one.
# This respects existing content if the user uploaded their own site.
if [[ ! -f "$WEB_ROOT/index.html" ]]; then
    cat > "$WEB_ROOT/index.html" <<EOF
<!DOCTYPE html>
<html>
<head><title>Welcome to nginx!</title><style>body{width:35em;margin:0 auto;font-family:Tahoma,Verdana,Arial,sans-serif;}</style></head>
<body><h1>Welcome to nginx!</h1><p>If you see this page, the nginx web server is successfully installed and working.</p></body>
</html>
EOF
fi

# Set permissions
chown -R www-data:www-data "/var/www/${DOMAIN}"
chmod -R 755 "/var/www/${DOMAIN}"

# Initial Nginx Config (HTTP only for Certbot)
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${WEB_ROOT};
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

# Enable Site
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/${DOMAIN}.conf"

# Restart Nginx to load config
systemctl restart nginx

# ==========================================
# 5. SSL Certificate (Certbot)
# ==========================================
green "🔒 申请 SSL 证书..."

# Stop Nginx briefly to prevent port conflict issues if standalone mode was needed (though we use webroot/nginx plugin usually)
# Here we use --nginx plugin which is robust
if certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect; then
    green "✅ 证书申请成功"
else
    red "❌ 证书申请失败. 请检查 DNS 解析是否正确."
    # Fallback attempt using webroot
    yellow "⚠️ 尝试使用 webroot 模式重试..."
    certbot certonly --webroot -w "$WEB_ROOT" -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive || { red "❌ 最终失败"; exit 1; }
fi

# ==========================================
# 6. Final Configuration (Nginx + Xray)
# ==========================================
green "🔧 写入最终配置..."

# 6.1 Xray Config
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${WS_PATH}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

# Ensure log dir exists
mkdir -p /var/log/xray
chown -R nobody:nogroup /var/log/xray

# Restart Xray
systemctl restart xray

# 6.2 Final Nginx Config (Reverse Proxy)
# We overwrite the config generated by Certbot to ensure the /ws path is proxy_passed correctly
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

    # Normal web traffic
    location / {
        try_files \$uri \$uri/ =404;
    }

    # Proxy WebSocket to Xray
    location ${WS_PATH} {
        if (\$http_upgrade != "websocket") {
            return 404;
        }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        # Show real IP in Xray logs
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

systemctl restart nginx

# ==========================================
# 7. BBR Optimization
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
# 8. Output Generation & Telegram (Optional)
# ==========================================

# Generate VLESS Link
VLESS_LINK="vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${WS_PATH}#${DOMAIN}"

# Generate QR Code
qrencode -o /root/vless-qrcode.png "$VLESS_LINK"

green "✅ 部署完成!"
echo ""
echo "------------------------------------------------------------------"
echo " VLESS 配置信息"
echo "------------------------------------------------------------------"
echo "地址 (Address): ${DOMAIN}"
echo "端口 (Port):    443"
echo "用户ID (UUID):  ${UUID}"
echo "传输 (Network): ws"
echo "路径 (Path):    ${WS_PATH}"
echo "安全 (TLS):     tls"
echo "------------------------------------------------------------------"
echo ""
echo "VLESS 链接:"
green "$VLESS_LINK"
echo ""

# Only execute Telegram logic if enabled
if $TG_ENABLE; then
    green "🤖 正在发送 Telegram 通知..."
    
    API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
    
    # 1. Send Text Message (MarkdownV2)
    # Escape special characters for MarkdownV2: _ * [ ] ( ) ~ ` > # + - = | { } . !
    ESCAPED_DOMAIN=$(echo "$DOMAIN" | sed 's/[.!]/\\&/g')
    ESCAPED_PATH=$(echo "$WS_PATH" | sed 's/[.!]/\\&/g')
    ESCAPED_LINK=$(echo "$VLESS_LINK" | sed 's/[][_*`~()<>#+=\-|{}.!]/\\&/g')
    
    TEXT="✅ *Deployment Successful*\n\nDomain: \`${ESCAPED_DOMAIN}\`\nPath: \`${ESCAPED_PATH}\`\n\n*Link (Click to Copy):*\n\`${ESCAPED_LINK}\`"
    
    curl -s -X POST "${API_URL}/sendMessage" -d chat_id="${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="$TEXT" >/dev/null
    
    # 2. Send QR Code
    if [[ -f /root/vless-qrcode.png ]]; then
        curl -s -F chat_id="${CHAT_ID}" -F document=@"/root/vless-qrcode.png" -F caption="Scan to Import" "${API_URL}/sendDocument" >/dev/null
    fi
    
    # 3. Setup Weekly Report Service (Optional)
    green "⏱️ 设置每周报告定时任务..."
    
    # Create monitoring script
    cat > /usr/local/bin/vpn-monitor.sh <<EOF_MON
#!/bin/bash
DOMAIN="${DOMAIN}"
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
API_URL="https://api.telegram.org/bot\${BOT_TOKEN}"

# Check Cert Expiry
CERT_FILE="/etc/letsencrypt/live/\${DOMAIN}/fullchain.pem"
if [[ -f "\$CERT_FILE" ]]; then
    EXPIRY=\$(openssl x509 -enddate -noout -in "\$CERT_FILE" | cut -d= -f2)
else
    EXPIRY="Unknown"
fi

# Check Server Load
LOAD=\$(uptime | awk -F'load average:' '{ print \$2 }')

MSG="📊 *Weekly Report*\nHost: \$(hostname)\nDomain: \${DOMAIN}\nLoad: \${LOAD}\nSSL Expiry: \${EXPIRY}"
# Simple escape
ESC_MSG=\$(echo "\$MSG" | sed 's/[.!]/\\\\&/g')

curl -s -X POST "\${API_URL}/sendMessage" -d chat_id="\${CHAT_ID}" -d parse_mode="MarkdownV2" -d text="\$ESC_MSG"
EOF_MON

    chmod +x /usr/local/bin/vpn-monitor.sh

    # Systemd Timer
    cat > /etc/systemd/system/vpn-monitor.service <<EOF_SVC
[Unit]
Description=VPN Weekly Report
[Service]
Type=oneshot
ExecStart=/usr/local/bin/vpn-monitor.sh
EOF_SVC

    cat > /etc/systemd/system/vpn-monitor.timer <<EOF_TMR
[Unit]
Description=Timer for VPN Weekly Report
[Timer]
OnCalendar=Mon 09:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF_TMR

    systemctl daemon-reload
    systemctl enable --now vpn-monitor.timer
else
    yellow "Telegram通知未启用，跳过相关服务配置。"
fi

green "🎉 全部完成! 如果您启用了Telegram，请检查消息。"
