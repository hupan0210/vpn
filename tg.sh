#!/usr/bin/env bash
#
# tg.sh - Telegram Management Bot Installation Script
# This script installs the necessary Python environment and deploys the nlbw_bot.py service.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

CONFIG_ENV="/etc/nlbwvpn/config.env"
BOT_SCRIPT="/usr/local/bin/nlbw_bot.py"
SERVICE_NAME="nlbw-bot"

green(){ echo -e "\033[1;32m$1\033[0m"; }
red(){ echo -e "\033[1;31m$1\033[0m"; }
yellow(){ echo -e "\033[1;33m$1\033[0m"; }

# Check Root
if [[ $EUID -ne 0 ]]; then
    red "❌ 错误: 此脚本必须以 root 用户运行。"
    exit 1
fi

green "🚀 启动 Telegram 管理机器人部署..."

# 1. Input Credentials
while true; do
    read -r -p "请输入 Telegram Bot Token (机器人令牌): " BOT_TOKEN
    if [[ -n "$BOT_TOKEN" ]]; then break; fi; red "Token 不能为空"
done

while true; do
    read -r -p "请输入 Telegram Chat ID (您的用户 ID，用于安全验证): " CHAT_ID
    if [[ -n "$CHAT_ID" ]]; then break; fi; red "Chat ID 不能为空"
done

# 2. Update Config Environment
mkdir -p /etc/nlbwvpn
# Ensure the config.env is updated/created
if [[ -f "$CONFIG_ENV" ]]; then
    # Use sed to safely replace or append
    sed -i "/^BOT_TOKEN=/d" "$CONFIG_ENV"
    sed -i "/^CHAT_ID=/d" "$CONFIG_ENV"
fi
cat >> "$CONFIG_ENV" <<EOF
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
TG_ENABLE="true"
# Nginx and Xray config paths used by the bot
XRAY_CONF="/usr/local/etc/xray/config.json"
NGINX_SERVICE="nginx"
XRAY_SERVICE="xray"
EOF
green "✅ 凭证已保存至 $CONFIG_ENV"

# 3. Install Dependencies
green "📦 安装 Python 依赖..."
apt-get update -y
apt-get install -y python3 python3-pip jq
if ! pip3 install pyTelegramBotAPI psutil; then
    red "❌ 安装 Python 依赖失败。请检查网络或 pip 版本。"
    exit 1
fi
green "✅ Python 依赖安装完成。"

# 4. Write Bot Logic
green "🧠 写入机器人核心逻辑到 $BOT_SCRIPT..."
# Note: The content of nlbw_bot.py will be placed here using a heredoc (EOF_BOT)
# For the sake of structure, the content is detailed in the next block.

# ----------------- Start of nlbw_bot.py Content (Embedded Here) -----------------
cat > "$BOT_SCRIPT" <<'EOF_BOT'
# ==============================================================================
# 🤖 nlbw_bot.py - Core Telegram Management Logic
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

# --- Configuration & Globals ---
CONFIG_ENV = "/etc/nlbwvpn/config.env"

def load_config():
    """Load configuration variables from config.env"""
    config = {}
    if not os.path.exists(CONFIG_ENV):
        print(f"Error: {CONFIG_ENV} not found.")
        return config
    
    with open(CONFIG_ENV, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                key, value = line.split('=', 1)
                config[key] = value.strip('"')
    return config

config = load_config()

# Read from environment or config.env
BOT_TOKEN = config.get("BOT_TOKEN")
CHAT_ID = config.get("CHAT_ID")
XRAY_CONF = config.get("XRAY_CONF", "/usr/local/etc/xray/config.json")
NGINX_SERVICE = config.get("NGINX_SERVICE", "nginx")
XRAY_SERVICE = config.get("XRAY_SERVICE", "xray")

if not BOT_TOKEN or not CHAT_ID:
    print("FATAL: BOT_TOKEN or CHAT_ID not configured.")
    exit(1)

# Ensure CHAT_ID is an integer for secure comparison
try:
    ALLOWED_CHAT_ID = int(CHAT_ID)
except ValueError:
    print("FATAL: CHAT_ID is not a valid integer.")
    exit(1)

bot = TeleBot(BOT_TOKEN, parse_mode='MarkdownV2')

# --- Helper Functions ---

def markdown_safe(text):
    """Escapes special characters in MarkdownV2"""
    # Characters to escape: []()~`>#+-=|{}.!
    for char in '[]()~`>#+-=|{}.!':
        text = text.replace(char, f'\\{char}')
    return text

def execute_command(cmd):
    """Execute shell command safely"""
    try:
        result = subprocess.run(cmd, shell=True, check=True, capture_output=True, text=True)
        return True, result.stdout
    except subprocess.CalledProcessError as e:
        return False, e.stderr
    except FileNotFoundError:
        return False, "Command not found."

# --- Xray Config Modification Functions ---

def generate_random_socks_creds():
    """Generates random, readable credentials for Socks5"""
    new_port = random.randint(20000, 50000)
    new_user = 'u' + ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
    new_pass = ''.join(random.choices(string.ascii_letters + string.digits, k=12))
    return new_port, new_user, new_pass

def get_xray_config():
    """Reads the current Xray config"""
    if not os.path.exists(XRAY_CONF):
        return None
    with open(XRAY_CONF, 'r') as f:
        return json.load(f)

def save_xray_config(config_data):
    """Writes the updated Xray config and fixes permissions"""
    with open(XRAY_CONF, 'w') as f:
        json.dump(config_data, f, indent=2)
    
    # CRITICAL: Fix permissions for Xray user (nobody/nogroup)
    os.chmod(XRAY_CONF, 0o644)
    subprocess.run(['chown', 'nobody:nogroup', XRAY_CONF], check=False, capture_output=True)

def update_socks5_inbound(port, user, password):
    """Modifies the Socks5 inbound in the Xray config"""
    config_data = get_xray_config()
    if not config_data:
        return False, "❌ 未找到 Xray 配置文件"

    updated = False
    for inbound in config_data.get('inbounds', []):
        if inbound.get('protocol') == 'socks':
            inbound['port'] = port
            inbound['settings']['accounts'][0]['user'] = user
            inbound['settings']['accounts'][0]['pass'] = password
            updated = True
            break
    
    if updated:
        save_xray_config(config_data)
        return True, "✅ Socks5 配置已更新"
    else:
        return False, "❌ 未找到 Socks5 Inbound 配置"

def get_current_info():
    """Extracts current VLESS and Socks5 info"""
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
            
    # Try to load domain from config.env
    info['domain'] = config.get("DOMAIN", "Unknown")
    return info

# --- Telegram Handlers ---

@bot.message_handler(func=lambda message: message.chat.id != ALLOWED_CHAT_ID, content_types=['text'])
def unauthorized(message):
    """Handle messages from unauthorized users"""
    bot.send_message(message.chat.id, f"❌ Unauthorized User: {message.chat.id}")

@bot.message_handler(commands=['start', 'help', 'menu'])
def send_welcome(message):
    """Displays the main menu"""
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    btn1 = types.KeyboardButton('📊 状态')
    btn2 = types.KeyboardButton('🔑 Socks5 管理')
    btn3 = types.KeyboardButton('🔄 重启服务')
    btn4 = types.KeyboardButton('ℹ️ 获取链接')
    markup.add(btn1, btn2, btn3, btn4)

    text = "🚀 *nlbwVPN 服务器管理面板*\n\n请选择操作或使用指令:"
    bot.send_message(message.chat.id, text, reply_markup=markup)

@bot.message_handler(regexp='📊 状态')
def handle_status(message):
    """Displays system status"""
    # Get System Info
    cpu_percent = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    # Get Service Status
    xray_status = subprocess.run(['systemctl', 'is-active', XRAY_SERVICE], capture_output=True, text=True).stdout.strip()
    nginx_status = subprocess.run(['systemctl', 'is-active', NGINX_SERVICE], capture_output=True, text=True).stdout.strip()
    
    # Format Uptime (approximate)
    boot_time_timestamp = psutil.boot_time()
    uptime_seconds = time.time() - boot_time_timestamp
    days = int(uptime_seconds // 86400)
    hours = int((uptime_seconds % 86400) // 3600)
    
    text = (f"🖥️ *服务器健康状态*\n"
            f"\\- **系统**: {markdown_safe(platform.system())} {markdown_safe(platform.release())}\n"
            f"\\- **运行时长**: {days} 天 {hours} 小时\n"
            f"\\- **CPU 占用**: {cpu_percent:.1f}%\n"
            f"\\- **内存占用**: {mem.percent:.1f}% \\({mem.used/1024**3:.2f}GB / {mem.total/1024**3:.2f}GB\\)\n"
            f"\\- **磁盘占用**: {disk.percent:.1f}% \\({disk.used/1024**3:.2f}GB / {disk.total/1024**3:.2f}GB\\)\n"
            f"\\- **Xray 服务**: {markdown_safe(xray_status)}\n"
            f"\\- **Nginx 服务**: {markdown_safe(nginx_status)}")
    bot.send_message(message.chat.id, text)

@bot.message_handler(regexp='🔄 重启服务')
def handle_restart_service(message):
    """Restart Xray and Nginx"""
    markup = types.InlineKeyboardMarkup()
    btn1 = types.InlineKeyboardButton("🔄 重启 Xray", callback_data='restart_xray')
    btn2 = types.InlineKeyboardButton("🔄 重启 Nginx", callback_data='restart_nginx')
    btn3 = types.InlineKeyboardButton("🔄 重启 全部", callback_data='restart_all')
    markup.add(btn1, btn2, btn3)
    bot.send_message(message.chat.id, "请选择要重启的服务:", reply_markup=markup)

@bot.callback_query_handler(func=lambda call: call.data.startswith('restart_'))
def callback_restart(call):
    service = call.data.split('_')[1]
    
    if service == 'all':
        services_to_restart = [XRAY_SERVICE, NGINX_SERVICE]
        msg_text = "🔄 正在重启 Xray 和 Nginx..."
    elif service == 'xray':
        services_to_restart = [XRAY_SERVICE]
        msg_text = "🔄 正在重启 Xray..."
    elif service == 'nginx':
        services_to_restart = [NGINX_SERVICE]
        msg_text = "🔄 正在重启 Nginx..."
    else:
        return

    bot.edit_message_text(msg_text, call.message.chat.id, call.message.message_id)
    
    results = []
    success = True
    for svc in services_to_restart:
        ok, output = execute_command(f'systemctl restart {svc}')
        if not ok: success = False
        results.append(f"{svc}: {'✅ 成功' if ok else f'❌ 失败: {markdown_safe(output)}'}")
        
    final_text = f"✅ *重启完成*\n" if success else f"❌ *重启失败*\n"
    final_text += '\\n'.join(results)
    bot.edit_message_text(final_text, call.message.chat.id, call.message.message_id)


@bot.message_handler(regexp='🔑 Socks5 管理')
def handle_socks_management(message):
    """Socks5 management menu"""
    markup = types.InlineKeyboardMarkup(row_width=1)
    btn1 = types.InlineKeyboardButton("🎲 随机重置 Socks5 账号", callback_data='socks_reset')
    btn2 = types.InlineKeyboardButton("✍️ 手动设置新账号 (指令)", callback_data='socks_manual_info')
    markup.add(btn1, btn2)
    bot.send_message(message.chat.id, "请选择 Socks5 账号管理方式:", reply_markup=markup)

@bot.callback_query_handler(func=lambda call: call.data == 'socks_reset')
def callback_socks_reset(call):
    """Resets Socks5 credentials randomly"""
    bot.edit_message_text("🎲 正在生成新的随机 Socks5 账号...", call.message.chat.id, call.message.message_id)
    
    new_port, new_user, new_pass = generate_random_socks_creds()
    ok, result = update_socks5_inbound(new_port, new_user, new_pass)
    
    if ok:
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        info_text = f"✅ *Socks5 账号已重置并重启 Xray*\\n\\n" \
                    f"Port: `{new_port}`\\n" \
                    f"User: `{new_user}`\\n" \
                    f"Pass: `{new_pass}`"
    else:
        info_text = f"❌ *重置失败:*{markdown_safe(result)}"

    bot.edit_message_text(info_text, call.message.chat.id, call.message.message_id)

@bot.callback_query_handler(func=lambda call: call.data == 'socks_manual_info')
def callback_socks_manual_info(call):
    """Instructions for manual Socks5 setup"""
    instructions = ("✍️ *手动设置指令格式:*\n\n"
                    "`/socks <Port> <User> <Password>`\n\n"
                    "例如：`/socks 16111 nlbw nlbw16111`\n\n"
                    "请发送指令进行设置。")
    bot.edit_message_text(instructions, call.message.chat.id, call.message.message_id)


@bot.message_handler(commands=['socks'])
def handle_socks_manual(message):
    """Handles manual Socks5 setup via command"""
    try:
        parts = message.text.split()
        if len(parts) != 4:
            raise ValueError("参数数量错误")
        
        port = int(parts[1])
        user = parts[2]
        password = parts[3]

        if not (1024 <= port <= 65535):
            raise ValueError("端口范围无效 (1024\\-65535)")

        bot.reply_to(message, "⚙️ 正在应用新的 Socks5 配置...")
        
        ok, result = update_socks5_inbound(port, user, password)

        if ok:
            execute_command(f'systemctl restart {XRAY_SERVICE}')
            info_text = f"✅ *Socks5 账号已手动设置并重启 Xray*\\n\\n" \
                        f"Port: `{port}`\\n" \
                        f"User: `{user}`\\n" \
                        f"Pass: `{password}`"
        else:
            info_text = f"❌ *设置失败:*{markdown_safe(result)}"
        
        bot.send_message(message.chat.id, info_text)

    except ValueError as e:
        bot.reply_to(message, f"❌ *指令错误或参数无效:*{markdown_safe(str(e))}\\n\\n请使用格式: `/socks <Port> <User> <Password>`")
    except Exception as e:
        bot.reply_to(message, f"❌ *发生未知错误:*{markdown_safe(str(e))}")


@bot.message_handler(regexp='ℹ️ 获取链接')
def handle_get_links(message):
    """Generates and sends the current connection links"""
    info = get_current_info()
    if not info or info.get('domain') == 'Unknown':
        bot.send_message(message.chat.id, "❌ *无法获取配置信息*\\n\\n请确认 Xray 已安装且域名已配置到 `/etc/nlbwvpn/config\\.env`")
        return

    domain = info['domain']
    # VLESS Link
    vless_link = f"vless://{info['uuid']}@{domain}:443?encryption=none&security=tls&type=ws&host={domain}&path={info['path']}#{domain}"
    # Socks5 Link
    socks_link = f"socks5://{info['socks_user']}:{info['socks_pass']}@{domain}:{info['socks_port']}#{domain}-Socks"

    text = (f"🔗 *当前节点连接信息*\n"
            f"域名: `{markdown_safe(domain)}`\n\n"
            f"1\\. **VLESS \\(WS\\+TLS\\):**\n"
            f"`{markdown_safe(vless_link)}`\n\n"
            f"2\\. **Socks5 \\(备用\\):**\n"
            f"`{markdown_safe(socks_link)}`")

    bot.send_message(message.chat.id, text)

# --- Main Loop ---
if __name__ == '__main__':
    green("🚀 Telegram 机器人正在运行...")
    bot.polling(none_stop=True, interval=3) # Poll every 3 seconds

EOF_BOT
# ----------------- End of nlbw_bot.py Content -----------------

chmod +x "$BOT_SCRIPT"
green "✅ 机器人核心逻辑写入完成。"

# 5. Create Systemd Service
green "🛠️ 创建 Systemd 服务..."
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

# 6. Enable and Start Service
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl restart ${SERVICE_NAME}.service

green "🎉 Telegram 管理机器人安装并启动成功！"
echo "请在 Telegram 中向您的机器人发送 /start 或 /menu 开始管理。"
