#!/usr/bin/env bash
#
# tg.sh - Telegram Management Bot for nlbwvpn
# Author: Hupan0210
# Description: Installs a Python-based Telegram bot to manage Xray/Nginx and monitor system status.
#

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Global Variables
CONFIG_ENV="/etc/nlbwvpn/config.env"
BOT_SCRIPT="/usr/local/bin/nlbw_bot.py"
SERVICE_NAME="nlbw-bot"

# Color helpers
green(){ echo -e "\033[1;32m$1\033[0m"; }
red(){ echo -e "\033[1;31m$1\033[0m"; }
yellow(){ echo -e "\033[1;33m$1\033[0m"; }

# Check Root
if [[ $EUID -ne 0 ]]; then
    red "❌ Error: This script must be run as root."
    exit 1
fi

green "🚀 启动 Telegram 管理机器人部署 (Final Version)..."

# 1. Credentials Input (Interactive)
# Only ask if not already in config, or force update if running interactively
while true; do
    read -r -p "请输入 Telegram Bot Token: " BOT_TOKEN
    if [[ -n "$BOT_TOKEN" ]]; then break; fi; red "Token 不能为空"
done

while true; do
    read -r -p "请输入 Telegram Chat ID (Admin ID): " CHAT_ID
    if [[ -n "$CHAT_ID" ]]; then break; fi; red "Chat ID 不能为空"
done

# 2. Save Configuration
mkdir -p /etc/nlbwvpn
# Remove old entries to prevent duplicates
if [[ -f "$CONFIG_ENV" ]]; then
    sed -i "/^BOT_TOKEN=/d" "$CONFIG_ENV"
    sed -i "/^CHAT_ID=/d" "$CONFIG_ENV"
fi
# Append new config
cat >> "$CONFIG_ENV" <<EOF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
XRAY_CONF="/usr/local/etc/xray/config.json"
NGINX_SERVICE="nginx"
XRAY_SERVICE="xray"
EOF
green "✅ 凭证已更新至 $CONFIG_ENV"

# 3. Install Dependencies
green "📦 安装系统与 Python 依赖..."
apt-get update -y
apt-get install -y python3 python3-pip jq

# Smart pip install (handles PEP 668 on Debian 12+)
green "⬇️ 安装 Python 库 (pyTelegramBotAPI, psutil)..."
if pip3 install pyTelegramBotAPI psutil --break-system-packages; then
    green "✅ Python 依赖安装成功 (with break-system-packages)"
else
    yellow "⚠️ 尝试标准 pip 安装..."
    pip3 install pyTelegramBotAPI psutil
fi

# 4. Generate Python Bot Script
green "🧠 写入机器人核心逻辑..."
cat > "$BOT_SCRIPT" <<'EOF_BOT'
# ==============================================================================
# 🤖 nlbw_bot.py - Server Management Bot
# ==============================================================================
import os
import subprocess
import json
import random
import string
import platform
import psutil
import time
from telebot import TeleBot, types

# --- Configuration ---
CONFIG_ENV = "/etc/nlbwvpn/config.env"

def load_config():
    config = {}
    if not os.path.exists(CONFIG_ENV): return config
    with open(CONFIG_ENV, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                parts = line.split('=', 1)
                if len(parts) == 2: config[parts[0]] = parts[1].strip('"')
    return config

config = load_config()
BOT_TOKEN = config.get("BOT_TOKEN")
CHAT_ID = config.get("CHAT_ID")
XRAY_CONF = config.get("XRAY_CONF", "/usr/local/etc/xray/config.json")
NGINX_SERVICE = config.get("NGINX_SERVICE", "nginx")
XRAY_SERVICE = config.get("XRAY_SERVICE", "xray")

if not BOT_TOKEN or not CHAT_ID:
    print("FATAL: BOT_TOKEN or CHAT_ID missing.")
    exit(1)

try:
    ALLOWED_CHAT_ID = int(CHAT_ID)
except ValueError:
    print("FATAL: CHAT_ID is not an integer.")
    exit(1)

bot = TeleBot(BOT_TOKEN, parse_mode='MarkdownV2')

# --- Helper Functions ---

def markdown_safe(text):
    """Escapes ALL special characters reserved in MarkdownV2"""
    if not isinstance(text, str): text = str(text)
    escape_chars = '_*[]()~`>#+-=|{}.!'
    for char in escape_chars:
        text = text.replace(char, f'\\{char}')
    return text

def get_size(bytes, suffix="B"):
    """Scale bytes to its proper format"""
    factor = 1024
    for unit in ["", "K", "M", "G", "T", "P"]:
        if bytes < factor:
            return f"{bytes:.2f}{unit}{suffix}"
        bytes /= factor
    return f"{bytes:.2f}P{suffix}"

def execute_command(cmd):
    try:
        result = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        return False, e.stderr
    except FileNotFoundError:
        return False, "Command not found."

# --- Core Logic ---

def generate_random_socks_creds():
    new_port = random.randint(20000, 50000)
    new_user = 'u' + ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
    new_pass = ''.join(random.choices(string.ascii_letters + string.digits, k=12))
    return new_port, new_user, new_pass

def get_xray_config():
    if not os.path.exists(XRAY_CONF): return None
    with open(XRAY_CONF, 'r') as f: return json.load(f)

def save_xray_config(config_data):
    with open(XRAY_CONF, 'w') as f: json.dump(config_data, f, indent=2)
    os.chmod(XRAY_CONF, 0o644)
    subprocess.run(['chown', 'nobody:nogroup', XRAY_CONF], check=False)

def update_socks5_inbound(port, user, password):
    config_data = get_xray_config()
    if not config_data: return False, "❌ Xray config file not found"
    updated = False
    for inbound in config_data.get('inbounds', []):
        if inbound.get('protocol') == 'socks':
            inbound['port'] = int(port)
            inbound['settings']['accounts'][0]['user'] = user
            inbound['settings']['accounts'][0]['pass'] = password
            updated = True
            break
    if updated:
        save_xray_config(config_data)
        return True, "✅ Socks5 updated"
    return False, "❌ Socks5 inbound not found"

def get_current_info():
    config_data = get_xray_config()
    if not config_data: return {}
    info = {}
    for inbound in config_data.get('inbounds', []):
        if inbound.get('protocol') == 'vless':
            info['uuid'] = inbound['settings']['clients'][0]['id']
            info['path'] = inbound['streamSettings']['wsSettings']['path']
        elif inbound.get('protocol') == 'socks':
            info['socks_port'] = inbound['port']
            info['socks_user'] = inbound['settings']['accounts'][0]['user']
            info['socks_pass'] = inbound['settings']['accounts'][0]['pass']
    info['domain'] = config.get("DOMAIN", "Unknown")
    return info

# --- Bot Handlers ---

@bot.message_handler(func=lambda message: message.chat.id != ALLOWED_CHAT_ID, content_types=['text'])
def unauthorized(message):
    bot.send_message(message.chat.id, "❌ Unauthorized Access")

@bot.message_handler(commands=['start', 'help', 'menu'])
def send_welcome(message):
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    markup.add(types.KeyboardButton('📊 状态'), types.KeyboardButton('🔑 Socks5 管理'),
               types.KeyboardButton('🔄 重启服务'), types.KeyboardButton('ℹ️ 获取链接'))
    bot.send_message(message.chat.id, "🚀 *服务器管理面板*\n请选择操作:", reply_markup=markup)

@bot.message_handler(regexp='📊 状态')
def handle_status(message):
    try:
        # System Stats
        cpu_p = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        net = psutil.net_io_counters()
        
        # Formatting
        sys_info = markdown_safe(f"{platform.system()} {platform.release()}")
        uptime_sec = time.time() - psutil.boot_time()
        days, rem = divmod(uptime_sec, 86400)
        hours, _ = divmod(rem, 3600)
        
        cpu_txt = markdown_safe(f"{cpu_p:.1f}%")
        mem_txt = markdown_safe(f"{mem.percent:.1f}% ({get_size(mem.used)} / {get_size(mem.total)})")
        disk_txt = markdown_safe(f"{disk.percent:.1f}%")
        net_up = markdown_safe(get_size(net.bytes_sent))
        net_down = markdown_safe(get_size(net.bytes_recv))
        
        # Service Checks
        xray_st = subprocess.run(['systemctl', 'is-active', XRAY_SERVICE], capture_output=True, text=True).stdout.strip()
        nginx_st = subprocess.run(['systemctl', 'is-active', NGINX_SERVICE], capture_output=True, text=True).stdout.strip()
        
        text = (f"🖥️ *服务器健康状态*\n"
                f"\\- *系统*: {sys_info}\n"
                f"\\- *运行*: {int(days)}天 {int(hours)}小时\n"
                f"\\- *CPU*: {cpu_txt}\n"
                f"\\- *内存*: {mem_txt}\n"
                f"\\- *磁盘*: {disk_txt}\n"
                f"\\- *流量*: ⬆️{net_up} / ⬇️{net_down}\n"
                f"\\- *Xray*: {markdown_safe(xray_st)}\n"
                f"\\- *Nginx*: {markdown_safe(nginx_st)}")
        
        bot.send_message(message.chat.id, text)
    except Exception as e:
        bot.send_message(message.chat.id, f"❌ Error: {markdown_safe(str(e))}")

@bot.message_handler(regexp='🔄 重启服务')
def handle_restart_service(message):
    markup = types.InlineKeyboardMarkup()
    markup.add(types.InlineKeyboardButton("重启 Xray", callback_data='restart_xray'),
               types.InlineKeyboardButton("重启 Nginx", callback_data='restart_nginx'))
    bot.send_message(message.chat.id, "请选择服务:", reply_markup=markup)

@bot.callback_query_handler(func=lambda call: call.data.startswith('restart_'))
def callback_restart(call):
    service = call.data.split('_')[1]
    svc_name = XRAY_SERVICE if service == 'xray' else NGINX_SERVICE
    bot.edit_message_text(f"🔄 重启 {service}...", call.message.chat.id, call.message.message_id)
    ok, out = execute_command(f'systemctl restart {svc_name}')
    res_text = f"✅ *{service} 重启成功*" if ok else f"❌ *{service} 失败*: {markdown_safe(out)}"
    bot.edit_message_text(res_text, call.message.chat.id, call.message.message_id)

@bot.message_handler(regexp='🔑 Socks5 管理')
def handle_socks_management(message):
    markup = types.InlineKeyboardMarkup()
    markup.add(types.InlineKeyboardButton("🎲 随机重置", callback_data='socks_reset'))
    bot.send_message(message.chat.id, "管理 Socks5 账号:", reply_markup=markup)

@bot.callback_query_handler(func=lambda call: call.data == 'socks_reset')
def callback_socks_reset(call):
    bot.edit_message_text("🎲 生成新账号中...", call.message.chat.id, call.message.message_id)
    port, user, pwd = generate_random_socks_creds()
    ok, res = update_socks5_inbound(port, user, pwd)
    if ok:
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        msg = (f"✅ *Socks5 已重置*\n"
               f"Port: `{port}`\nUser: `{markdown_safe(user)}`\nPass: `{markdown_safe(pwd)}`")
    else:
        msg = f"❌ Error: {markdown_safe(res)}"
    bot.edit_message_text(msg, call.message.chat.id, call.message.message_id)

@bot.message_handler(regexp='ℹ️ 获取链接')
def handle_get_links(message):
    info = get_current_info()
    dom = info.get('domain', 'Unknown')
    if dom == 'Unknown':
        bot.send_message(message.chat.id, "❌ 无法读取域名")
        return
        
    vless = f"vless://{info['uuid']}@{dom}:443?encryption=none&security=tls&type=ws&host={dom}&path={info['path']}#{dom}"
    socks = f"socks5://{info['socks_user']}:{info['socks_pass']}@{dom}:{info['socks_port']}#{dom}-Socks"
    
    text = (f"🔗 *节点连接信息*\n"
            f"域名: `{markdown_safe(dom)}`\n\n"
            f"1️⃣ *VLESS (WS+TLS)*:\n`{markdown_safe(vless)}`\n\n"
            f"2️⃣ *Socks5 (备用)*:\n`{markdown_safe(socks)}`")
    bot.send_message(message.chat.id, text)

# --- Start ---
if __name__ == '__main__':
    print("🚀 Bot Started...")
    bot.polling(none_stop=True, interval=2)
EOF_BOT
chmod +x "$BOT_SCRIPT"
green "✅ 机器人核心逻辑写入完成。"

# 5. Create Systemd Service
green "🛠️ 配置系统服务 (Systemd)..."
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF_SVC
[Unit]
Description=nlbw VPN Management Bot
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${BOT_SCRIPT}
Restart=always
User=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF_SVC

# 6. Enable and Start
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl restart ${SERVICE_NAME}.service

echo ""
green "🎉 部署完成! Telegram 机器人已上线。"
echo "请发送 /start 开始管理。"
