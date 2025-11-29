#!/usr/bin/env bash
#
# tg.sh - Telegram Management Bot (Multi-User Edition)
#
# Features:
# 1. Monitor System Status & Traffic
# 2. Manage Socks5 (Reset/Add)
# 3. Manage VLESS (Add Users)
# 4. Auto-fix Python env (PEP 668)
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

green "🚀 启动 Telegram 机器人部署 (多用户版)..."

# 1. Credentials Input
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
if [[ -f "$CONFIG_ENV" ]]; then
    sed -i "/^BOT_TOKEN=/d" "$CONFIG_ENV"
    sed -i "/^CHAT_ID=/d" "$CONFIG_ENV"
fi
cat >> "$CONFIG_ENV" <<EOF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
XRAY_CONF="/usr/local/etc/xray/config.json"
NGINX_SERVICE="nginx"
XRAY_SERVICE="xray"
EOF
green "✅ 凭证已保存。"

# 3. Install Dependencies
green "📦 安装依赖..."
apt-get update -y
apt-get install -y python3 python3-pip jq

green "⬇️ 安装 Python 库..."
# Handle PEP 668 automatically
if pip3 install pyTelegramBotAPI psutil --break-system-packages; then
    green "✅ Python 依赖安装成功"
else
    yellow "⚠️ 尝试标准 pip 安装..."
    pip3 install pyTelegramBotAPI psutil
fi

# 4. Generate Python Bot Script
green "🧠 写入机器人逻辑 (包含多用户功能)..."
cat > "$BOT_SCRIPT" <<'EOF_BOT'
# ==============================================================================
# 🤖 nlbw_bot.py - Multi-User Edition
# ==============================================================================
import os
import subprocess
import json
import random
import string
import platform
import psutil
import time
import uuid
from telebot import TeleBot, types

# --- Config ---
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
XRAY_SERVICE = config.get("XRAY_SERVICE", "xray")
NGINX_SERVICE = config.get("NGINX_SERVICE", "nginx")

if not BOT_TOKEN or not CHAT_ID: exit(1)
try: ALLOWED_CHAT_ID = int(CHAT_ID)
except: exit(1)

bot = TeleBot(BOT_TOKEN, parse_mode='MarkdownV2')

# --- Helpers ---
def markdown_safe(text):
    if not isinstance(text, str): text = str(text)
    for char in '_*[]()~`>#+-=|{}.!':
        text = text.replace(char, f'\\{char}')
    return text

def get_size(bytes, suffix="B"):
    factor = 1024
    for unit in ["", "K", "M", "G", "T", "P"]:
        if bytes < factor: return f"{bytes:.2f}{unit}{suffix}"
        bytes /= factor
    return f"{bytes:.2f}P{suffix}"

def execute_command(cmd):
    try:
        res = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        return True, res.stdout
    except subprocess.CalledProcessError as e: return False, e.stderr

def get_xray_config():
    if not os.path.exists(XRAY_CONF): return None
    with open(XRAY_CONF, 'r') as f: return json.load(f)

def save_xray_config(data):
    with open(XRAY_CONF, 'w') as f: json.dump(data, f, indent=2)
    os.chmod(XRAY_CONF, 0o644)
    subprocess.run(['chown', 'nobody:nogroup', XRAY_CONF], check=False)

def get_domain_and_path():
    data = get_xray_config()
    path = "/"
    if data:
        for inbound in data.get('inbounds', []):
            if inbound.get('protocol') == 'vless':
                path = inbound['streamSettings']['wsSettings']['path']
                break
    return config.get("DOMAIN", "Unknown"), path

# --- Add User Logic ---

def add_vless_user(remarks):
    data = get_xray_config()
    if not data: return False, "Config missing"
    
    new_uuid = str(uuid.uuid4())
    # Find VLESS inbound
    for inbound in data.get('inbounds', []):
        if inbound.get('protocol') == 'vless':
            # Create user dict. Using email as remarks
            new_client = {"id": new_uuid, "email": remarks, "level": 0}
            inbound['settings']['clients'].append(new_client)
            save_xray_config(data)
            return True, new_uuid
            
    return False, "VLESS Inbound not found"

def add_socks_user(remarks):
    data = get_xray_config()
    if not data: return False, "Config missing"
    
    new_user = 'u' + ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
    new_pass = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
    
    # Find Socks inbound
    for inbound in data.get('inbounds', []):
        if inbound.get('protocol') == 'socks':
            new_acc = {"user": new_user, "pass": new_pass}
            # Append to accounts list
            inbound['settings']['accounts'].append(new_acc)
            # Retrieve port
            port = inbound['port']
            save_xray_config(data)
            return True, (port, new_user, new_pass)
            
    return False, "Socks Inbound not found"

# --- Bot Handlers ---

@bot.message_handler(func=lambda m: m.chat.id != ALLOWED_CHAT_ID, content_types=['text'])
def unauthorized(m): bot.send_message(m.chat.id, "❌ Unauthorized")

@bot.message_handler(commands=['start', 'menu'])
def menu(m):
    mk = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    mk.add(types.KeyboardButton('📊 状态'), types.KeyboardButton('👥 新增用户'),
           types.KeyboardButton('🔄 重启服务'), types.KeyboardButton('ℹ️ 获取链接'))
    bot.send_message(m.chat.id, "🚀 *面板已就绪*", reply_markup=mk)

@bot.message_handler(regexp='📊 状态')
def status(m):
    try:
        cpu = psutil.cpu_percent(1)
        mem = psutil.virtual_memory()
        net = psutil.net_io_counters()
        uptime = time.time() - psutil.boot_time()
        d, rem = divmod(uptime, 86400)
        h, _ = divmod(rem, 3600)
        
        xray = subprocess.run(['systemctl','is-active',XRAY_SERVICE], capture_output=True, text=True).stdout.strip()
        
        txt = (f"🖥️ *服务器状态*\n"
               f"\\- *运行*: {int(d)}天 {int(h)}小时\n"
               f"\\- *CPU*: {markdown_safe(f'{cpu:.1f}%')}\n"
               f"\\- *内存*: {markdown_safe(f'{mem.percent:.1f}%')}\n"
               f"\\- *流量*: ⬆️{markdown_safe(get_size(net.bytes_sent))} ⬇️{markdown_safe(get_size(net.bytes_recv))}\n"
               f"\\- *Xray*: {markdown_safe(xray)}")
        bot.send_message(m.chat.id, txt)
    except Exception as e: bot.send_message(m.chat.id, f"Error: {e}")

@bot.message_handler(regexp='🔄 重启服务')
def restart_menu(m):
    mk = types.InlineKeyboardMarkup()
    mk.add(types.InlineKeyboardButton("重启 Xray", callback_data='res_xray'),
           types.InlineKeyboardButton("重启 Nginx", callback_data='res_nginx'))
    bot.send_message(m.chat.id, "选择服务:", reply_markup=mk)

@bot.callback_query_handler(func=lambda c: c.data.startswith('res_'))
def restart_handler(c):
    svc = XRAY_SERVICE if c.data == 'res_xray' else NGINX_SERVICE
    bot.edit_message_text(f"🔄 重启 {svc}...", c.message.chat.id, c.message.message_id)
    execute_command(f'systemctl restart {svc}')
    bot.edit_message_text(f"✅ *{svc} 重启成功*", c.message.chat.id, c.message.message_id)

@bot.message_handler(regexp='ℹ️ 获取链接')
def get_links(m):
    dom, path = get_domain_and_path()
    if dom == "Unknown": return bot.send_message(m.chat.id, "❌ 域名未知")
    
    # Get Admin (First) Users
    data = get_xray_config()
    uuid = data['inbounds'][0]['settings']['clients'][0]['id']
    
    # Find socks
    s_port = s_user = s_pass = ""
    for ib in data['inbounds']:
        if ib['protocol'] == 'socks':
            s_port = ib['port']
            s_user = ib['settings']['accounts'][0]['user']
            s_pass = ib['settings']['accounts'][0]['pass']
            break
            
    vless = f"vless://{uuid}@{dom}:443?encryption=none&security=tls&type=ws&host={dom}&path={path}#{dom}-Admin"
    socks = f"socks5://{s_user}:{s_pass}@{dom}:{s_port}#{dom}-Admin"
    
    bot.send_message(m.chat.id, f"🔗 *管理员默认节点*\n\nVLESS:\n`{markdown_safe(vless)}`\n\nSocks5:\n`{markdown_safe(socks)}`")

# --- User Management ---

@bot.message_handler(regexp='👥 新增用户')
def add_user_menu(m):
    mk = types.InlineKeyboardMarkup()
    mk.add(types.InlineKeyboardButton("➕ 新增 VLESS 朋友", callback_data='add_vless'),
           types.InlineKeyboardButton("➕ 新增 Socks5 朋友", callback_data='add_socks'))
    bot.send_message(m.chat.id, "请选择要添加的账号类型:", reply_markup=mk)

@bot.callback_query_handler(func=lambda c: c.data == 'add_vless')
def handler_add_vless(c):
    bot.edit_message_text("⏳ 正在生成 VLESS 账号...", c.message.chat.id, c.message.message_id)
    # Use timestamp as simple remark
    remark = f"friend_{int(time.time())}"
    ok, res = add_vless_user(remark)
    
    if ok:
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        dom, path = get_domain_and_path()
        link = f"vless://{res}@{dom}:443?encryption=none&security=tls&type=ws&host={dom}&path={path}#Friend"
        
        msg = (f"✅ *新增 VLESS 成功*\n"
               f"UUID: `{markdown_safe(res)}`\n"
               f"备注: `{markdown_safe(remark)}`\n\n"
               f"🔗 *分享链接*:\n`{markdown_safe(link)}`")
    else:
        msg = f"❌ 失败: {markdown_safe(res)}"
    
    bot.edit_message_text(msg, c.message.chat.id, c.message.message_id)

@bot.callback_query_handler(func=lambda c: c.data == 'add_socks')
def handler_add_socks(c):
    bot.edit_message_text("⏳ 正在生成 Socks5 账号...", c.message.chat.id, c.message.message_id)
    remark = f"friend_{int(time.time())}"
    ok, res = add_socks_user(remark)
    
    if ok:
        port, user, pwd = res
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        dom, _ = get_domain_and_path()
        link = f"socks5://{user}:{pwd}@{dom}:{port}#Friend-Socks"
        
        msg = (f"✅ *新增 Socks5 成功*\n"
               f"Port: `{port}` (共用)\n"
               f"User: `{markdown_safe(user)}`\n"
               f"Pass: `{markdown_safe(pwd)}`\n\n"
               f"🔗 *分享链接*:\n`{markdown_safe(link)}`")
    else:
        msg = f"❌ 失败: {markdown_safe(res)}"

    bot.edit_message_text(msg, c.message.chat.id, c.message.message_id)

# --- Start ---
if __name__ == '__main__':
    print("🚀 Bot Started...")
    bot.polling(none_stop=True)
EOF_BOT
chmod +x "$BOT_SCRIPT"
green "✅ 机器人核心逻辑写入完成。"

# 5. Service
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl restart ${SERVICE_NAME}.service

echo ""
green "🎉 部署完成! 您的机器人现在支持【新增用户】功能了。"
