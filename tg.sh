#!/usr/bin/env bash
#
# tg.sh - Telegram Server Management Bot (V6 Final Verified)
# Verified Fixes: HTML Escaping, QR Temp Files, Python Path
#

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Global Config ---
CONFIG_ENV="/etc/nlbwvpn/config.env"
BOT_SCRIPT="/usr/local/bin/nlbw_bot.py"
SERVICE_NAME="nlbw-bot"

# --- Colors ---
green(){ echo -e "\033[1;32m$1\033[0m"; }
red(){ echo -e "\033[1;31m$1\033[0m"; }
yellow(){ echo -e "\033[1;33m$1\033[0m"; }

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
    red "❌ Error: This script must be run as root."
    exit 1
fi

green "🚀 启动 Telegram 机器人部署 (V6 Verified)..."

# --- 1. Input Credentials ---
while true; do
    read -r -p "请输入 Telegram Bot Token: " BOT_TOKEN
    if [[ -n "$BOT_TOKEN" ]]; then break; fi; red "Token 不能为空"
done

while true; do
    read -r -p "请输入 Telegram Chat ID (超级管理员): " CHAT_ID
    if [[ -n "$CHAT_ID" ]]; then break; fi; red "Chat ID 不能为空"
done

# --- 2. Save Config ---
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

# --- 3. Install Dependencies ---
green "📦 安装依赖 (Python3, pip, qrencode, speedtest)..."
apt-get update -y
apt-get install -y python3 python3-pip jq qrencode speedtest-cli

green "⬇️ 安装 Python 库..."
# Handle PEP 668 (Debian 12+)
if pip3 install pyTelegramBotAPI psutil --break-system-packages; then
    green "✅ Python 依赖安装成功"
else
    yellow "⚠️ 尝试标准 pip 安装..."
    pip3 install pyTelegramBotAPI psutil
fi

# --- 4. Write Python Script ---
green "🧠 写入机器人代码..."
cat > "$BOT_SCRIPT" <<'EOF_BOT'
# ==============================================================================
# 🤖 nlbw_bot.py - V6 Verified
# ==============================================================================
import os
import subprocess
import json
import platform
import psutil
import time
import uuid
import sys
import html
from telebot import TeleBot, types

# --- Config ---
CONFIG_ENV = "/etc/nlbwvpn/config.env"
ADMIN_FILE = "/etc/nlbwvpn/admins.json"
XRAY_CONF = "/usr/local/etc/xray/config.json"
NGINX_SERVICE = "nginx"
XRAY_SERVICE = "xray"

config = {}
if os.path.exists(CONFIG_ENV):
    with open(CONFIG_ENV, 'r') as f:
        for line in f:
            if '=' in line and not line.startswith('#'):
                k, v = line.strip().split('=', 1)
                config[k] = v.strip('"')

BOT_TOKEN = config.get("BOT_TOKEN")
SUPER_ADMIN_ID = config.get("CHAT_ID")

if not BOT_TOKEN or not SUPER_ADMIN_ID: sys.exit(1)

# Ensure qrencode exists
subprocess.run("apt-get install -y qrencode", shell=True, check=False)

bot = TeleBot(BOT_TOKEN, parse_mode='HTML')

# --- Helpers ---
def get_admins():
    if not os.path.exists(ADMIN_FILE):
        admins = [int(SUPER_ADMIN_ID)]
        save_admins(admins)
        return admins
    try:
        with open(ADMIN_FILE, 'r') as f: return json.load(f)
    except: return [int(SUPER_ADMIN_ID)]

def save_admins(admin_list):
    with open(ADMIN_FILE, 'w') as f: json.dump(admin_list, f)

def is_admin(chat_id): return chat_id in get_admins()

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

def send_qr_code(chat_id, data, caption):
    """Generates a QR code image and sends it"""
    try:
        # Use random filename to avoid conflicts
        png_path = f"/tmp/qr_{uuid.uuid4()}.png"
        subprocess.run(['qrencode', '-o', png_path, '-s', '6', data], check=True)
        with open(png_path, 'rb') as photo:
            bot.send_photo(chat_id, photo, caption=caption)
        os.remove(png_path)
    except Exception as e:
        bot.send_message(chat_id, f"❌ 二维码生成失败: {e}")

# --- Bot Handlers ---

@bot.message_handler(func=lambda m: not is_admin(m.chat.id), content_types=['text'])
def unauthorized(m): bot.send_message(m.chat.id, "❌ 无权访问")

@bot.message_handler(commands=['start', 'menu'])
def menu(m):
    mk = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    mk.add(types.KeyboardButton('📊 状态'), types.KeyboardButton('👥 用户管理'),
           types.KeyboardButton('👮 管理员'), types.KeyboardButton('🛠️ 实用工具'),
           types.KeyboardButton('ℹ️ 获取所有链接'))
    bot.send_message(m.chat.id, "🚀 <b>V6 终极管理面板</b>", reply_markup=mk)

# --- 1. STATUS ---
@bot.message_handler(regexp='📊 状态')
def status(m):
    try:
        sys_info = f"{platform.system()} {platform.release()}"
        cpu = psutil.cpu_percent(1)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        net = psutil.net_io_counters()
        uptime = time.time() - psutil.boot_time()
        d, rem = divmod(uptime, 86400)
        h, _ = divmod(rem, 3600)
        
        xray_st = subprocess.run(['systemctl','is-active',XRAY_SERVICE], capture_output=True, text=True).stdout.strip()
        nginx_st = subprocess.run(['systemctl','is-active',NGINX_SERVICE], capture_output=True, text=True).stdout.strip()
        
        txt = (f"🖥️ <b>服务器健康状态</b>\n"
               f"- <b>系统</b>: {html.escape(sys_info)}\n"
               f"- <b>运行</b>: {int(d)}天 {int(h)}小时\n"
               f"- <b>CPU</b>: {cpu:.1f}%\n"
               f"- <b>内存</b>: {mem.percent:.1f}% ({get_size(mem.used)} / {get_size(mem.total)})\n"
               f"- <b>磁盘</b>: {disk.percent:.1f}% ({get_size(disk.used)} / {get_size(disk.total)})\n"
               f"- <b>流量</b>: ⬆️{get_size(net.bytes_sent)} ⬇️{get_size(net.bytes_recv)}\n"
               f"- <b>Xray</b>: {xray_st}\n"
               f"- <b>Nginx</b>: {nginx_st}")
        bot.send_message(m.chat.id, txt)
    except Exception as e: bot.send_message(m.chat.id, f"Error: {e}")

# --- 2. USER MGMT ---
@bot.message_handler(regexp='👥 用户管理')
def user_menu(m):
    mk = types.InlineKeyboardMarkup()
    mk.add(types.InlineKeyboardButton("➕ 新增 VLESS", callback_data='add_vless'),
           types.InlineKeyboardButton("➕ 新增 Socks5", callback_data='add_socks'))
    mk.add(types.InlineKeyboardButton("📋 管理 VLESS (改/删/码)", callback_data='list_vless'),
           types.InlineKeyboardButton("📋 管理 Socks5 (改/删/码)", callback_data='list_socks'))
    bot.send_message(m.chat.id, "👥 <b>用户账号管理</b>", reply_markup=mk)

@bot.callback_query_handler(func=lambda c: True)
def handle_all(c):
    try:
        if c.data.startswith('add_'): handle_add_user(c)
        elif c.data.startswith('list_'): handle_list_user(c)
        elif c.data.startswith('manage_'): handle_manage_user(c)
        elif c.data.startswith('del_'): handle_del_user(c)
        elif c.data.startswith('mod_'): handle_mod_user(c)
        elif c.data.startswith('qr_'): handle_get_qr(c)
        elif c.data.startswith('adm_'): handle_admin(c)
        elif c.data.startswith('tool_'): handle_tools(c)
    except Exception as e:
        bot.send_message(c.message.chat.id, f"❌ 错误: {str(e)}")

# ... Add Logic ...
def handle_add_user(c):
    if c.data == 'add_vless':
        msg = bot.send_message(c.message.chat.id, "✍️ <b>请输入 VLESS 备注 (英文):</b>")
        bot.register_next_step_handler(msg, add_vless_step)
    elif c.data == 'add_socks':
        msg = bot.send_message(c.message.chat.id, "✍️ <b>请输入: 用户名 密码</b> (空格分隔):")
        bot.register_next_step_handler(msg, add_socks_step)
    bot.answer_callback_query(c.id)

def add_vless_step(m):
    try:
        remark = m.text.strip()
        data = get_xray_config()
        new_id = str(uuid.uuid4())
        inb = next(i for i in data['inbounds'] if i['protocol']=='vless')
        inb['settings']['clients'].append({"id": new_id, "email": remark, "level": 0})
        save_xray_config(data)
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        dom, path = get_domain_and_path()
        link = f"vless://{new_id}@{dom}:443?encryption=none&security=tls&type=ws&host={dom}&path={path}#{remark}"
        bot.send_message(m.chat.id, f"✅ <b>VLESS 添加成功</b>\n\n<code>{html.escape(link)}</code>")
        send_qr_code(m.chat.id, link, f"QR: {remark}")
    except Exception as e: bot.send_message(m.chat.id, f"❌ 失败: {e}")

def add_socks_step(m):
    try:
        u, p = m.text.split()
        data = get_xray_config()
        inb = next(i for i in data['inbounds'] if i['protocol']=='socks')
        inb['settings']['accounts'].append({"user": u, "pass": p})
        port = inb['port']
        save_xray_config(data)
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        dom, _ = get_domain_and_path()
        link = f"socks5://{u}:{p}@{dom}:{port}#{u}"
        bot.send_message(m.chat.id, f"✅ <b>Socks5 添加成功</b>\n\n<code>{html.escape(link)}</code>")
        send_qr_code(m.chat.id, link, f"QR: {u}")
    except: bot.send_message(m.chat.id, "❌ 格式错误 (使用空格分隔)")

# ... List & Manage ...
def handle_list_user(c):
    data = get_xray_config()
    mk = types.InlineKeyboardMarkup()
    if c.data == 'list_vless':
        clients = next(i for i in data['inbounds'] if i['protocol']=='vless')['settings']['clients']
        for cl in clients:
            mk.add(types.InlineKeyboardButton(f"👤 {cl.get('email','User')}", callback_data=f"manage_vless_{cl['id']}"))
    else:
        accs = next(i for i in data['inbounds'] if i['protocol']=='socks')['settings']['accounts']
        for ac in accs:
            mk.add(types.InlineKeyboardButton(f"👤 {ac['user']}", callback_data=f"manage_socks_{ac['user']}"))
    bot.edit_message_text("📋 <b>选择要管理的用户:</b>", c.message.chat.id, c.message.message_id, reply_markup=mk)

def handle_manage_user(c):
    parts = c.data.split('_', 2)
    mode = parts[1]; ident = parts[2]
    
    mk = types.InlineKeyboardMarkup()
    if mode == 'vless':
        mk.add(types.InlineKeyboardButton("✏️ 修改备注", callback_data=f"mod_vless_{ident}"))
    else:
        mk.add(types.InlineKeyboardButton("✏️ 修改密码", callback_data=f"mod_socks_{ident}"))
    
    mk.add(types.InlineKeyboardButton("📷 获取二维码 / 链接", callback_data=f"qr_{mode}_{ident}"))
    mk.add(types.InlineKeyboardButton("❌ 删除用户", callback_data=f"del_{mode}_{ident}"))
    mk.add(types.InlineKeyboardButton("🔙 返回", callback_data=f"list_{mode}"))
    
    bot.edit_message_text(f"⚙️ <b>管理用户:</b> <code>{ident}</code>", c.message.chat.id, c.message.message_id, reply_markup=mk)

# ... QR Handler ...
def handle_get_qr(c):
    parts = c.data.split('_', 2)
    mode = parts[1]; ident = parts[2]
    dom, path = get_domain_and_path()
    data = get_xray_config()
    
    link = ""
    caption = ""
    
    if mode == 'vless':
        clients = next(i for i in data['inbounds'] if i['protocol']=='vless')['settings']['clients']
        target = next((x for x in clients if x['id'] == ident), None)
        if target:
            link = f"vless://{ident}@{dom}:443?encryption=none&security=tls&type=ws&host={dom}&path={path}#{target['email']}"
            caption = f"👤 <b>VLESS:</b> {target['email']}"
    else:
        accs = next(i for i in data['inbounds'] if i['protocol']=='socks')['settings']['accounts']
        target = next((x for x in accs if x['user'] == ident), None)
        if target:
            inb = next(i for i in data['inbounds'] if i['protocol']=='socks')
            link = f"socks5://{target['user']}:{target['pass']}@{dom}:{inb['port']}#{target['user']}"
            caption = f"👤 <b>Socks5:</b> {target['user']}"
            
    if link:
        bot.send_message(c.message.chat.id, f"{caption}\n<code>{html.escape(link)}</code>", parse_mode='HTML')
        send_qr_code(c.message.chat.id, link, "📷 扫码导入")
        bot.answer_callback_query(c.id)
    else:
        bot.answer_callback_query(c.id, "❌ 用户未找到")

# ... Modify & Delete ...
def handle_mod_user(c):
    mode = c.data.split('_')[1]; ident = c.data.split('_', 2)[2]
    if mode == 'vless':
        msg = bot.send_message(c.message.chat.id, f"✍️ <b>请输入新备注:</b>")
        bot.register_next_step_handler(msg, lambda m: do_mod_vless(m, ident))
    else:
        msg = bot.send_message(c.message.chat.id, f"✍️ <b>请输入新密码:</b>")
        bot.register_next_step_handler(msg, lambda m: do_mod_socks(m, ident))
    bot.answer_callback_query(c.id)

def do_mod_vless(m, uuid_target):
    try:
        new_remark = m.text.strip()
        data = get_xray_config()
        clients = next(i for i in data['inbounds'] if i['protocol']=='vless')['settings']['clients']
        for c in clients:
            if c['id'] == uuid_target: c['email'] = new_remark
        save_xray_config(data)
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        bot.send_message(m.chat.id, f"✅ 备注更新: {html.escape(new_remark)}")
    except: pass

def do_mod_socks(m, user_target):
    try:
        new_pass = m.text.strip()
        data = get_xray_config()
        accs = next(i for i in data['inbounds'] if i['protocol']=='socks')['settings']['accounts']
        for a in accs:
            if a['user'] == user_target: a['pass'] = new_pass
        save_xray_config(data)
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        bot.send_message(m.chat.id, f"✅ 密码更新: {html.escape(new_pass)}")
    except: pass

def handle_del_user(c):
    parts = c.data.split('_', 2); mode = parts[1]; tgt = parts[2]
    data = get_xray_config()
    changed = False
    if mode == 'vless':
        clients = next(i for i in data['inbounds'] if i['protocol']=='vless')['settings']['clients']
        if len(clients) <= 1: return bot.answer_callback_query(c.id, "❌ 不能删除最后的主账号", show_alert=True)
        new_c = [x for x in clients if x['id'] != tgt]
        if len(new_c) < len(clients):
            next(i for i in data['inbounds'] if i['protocol']=='vless')['settings']['clients'] = new_c
            changed = True
    else:
        accs = next(i for i in data['inbounds'] if i['protocol']=='socks')['settings']['accounts']
        if len(accs) <= 1: return bot.answer_callback_query(c.id, "❌ 不能删除最后的主账号", show_alert=True)
        new_a = [x for x in accs if x['user'] != tgt]
        if len(new_a) < len(accs):
            next(i for i in data['inbounds'] if i['protocol']=='socks')['settings']['accounts'] = new_a
            changed = True
    if changed:
        save_xray_config(data)
        execute_command(f'systemctl restart {XRAY_SERVICE}')
        bot.answer_callback_query(c.id, "✅ 已删除")
        bot.edit_message_text(f"🗑️ <b>已删除:</b> {tgt}", c.message.chat.id, c.message.message_id)

# --- 3. GET ALL LINKS (Updated) ---
@bot.message_handler(regexp='ℹ️ 获取所有链接')
def get_all_links(m):
    try:
        dom, path = get_domain_and_path()
        data = get_xray_config()
        
        v_clients = next(i for i in data['inbounds'] if i['protocol']=='vless')['settings']['clients']
        s_in = next(i for i in data['inbounds'] if i['protocol']=='socks')
        s_accs = s_in['settings']['accounts']
        s_port = s_in['port']
        
        msg = "🔗 <b>当前所有可用链接:</b>\n\n"
        
        msg += "🟢 <b>=== VLESS ===</b>\n"
        admin_v_link = ""
        for i, cl in enumerate(v_clients):
            remark = cl.get('email', 'User')
            if i == 0: remark += " (Admin)"
            link = f"vless://{cl['id']}@{dom}:443?encryption=none&security=tls&type=ws&host={dom}&path={path}#{remark}"
            if i == 0: admin_v_link = link
            msg += f"👤 <b>{html.escape(remark)}</b>:\n<code>{html.escape(link)}</code>\n\n"
            
        msg += "🟡 <b>=== Socks5 ===</b>\n"
        for i, ac in enumerate(s_accs):
            u = ac['user']; p = ac['pass']
            tag = " (Admin)" if i == 0 else ""
            link = f"socks5://{u}:{p}@{dom}:{s_port}#{u}{tag}"
            msg += f"👤 <b>{html.escape(u)}{tag}</b>:\n<code>{html.escape(link)}</code>\n\n"
            
        bot.send_message(m.chat.id, msg)
        
        if admin_v_link:
            send_qr_code(m.chat.id, admin_v_link, "📷 主管理员 VLESS 二维码")
            
    except Exception as e: bot.send_message(m.chat.id, f"Error: {e}")

# --- Admins & Tools ---
@bot.message_handler(regexp='👮 管理员')
def admin_menu(m):
    mk = types.InlineKeyboardMarkup()
    mk.add(types.InlineKeyboardButton("➕ 添加", callback_data='adm_add'),
           types.InlineKeyboardButton("➖ 移除", callback_data='adm_del'),
           types.InlineKeyboardButton("📜 列表", callback_data='adm_list'))
    bot.send_message(m.chat.id, "👮 <b>管理员设置</b>", reply_markup=mk)

def handle_admin(c):
    act = c.data.split('_')[1]
    if act == 'list':
        admins = get_admins()
        txt = "📜 <b>管理员:</b>\n" + "\n".join([f"<code>{u}</code>" for u in admins])
        bot.edit_message_text(txt, c.message.chat.id, c.message.message_id)
    elif act == 'add':
        msg = bot.send_message(c.message.chat.id, "✍️ <b>输入新管理员 TG ID:</b>")
        bot.register_next_step_handler(msg, lambda m: process_admin_op(m, 'add'))
    elif act == 'del':
        msg = bot.send_message(c.message.chat.id, "✍️ <b>输入要移除的 TG ID:</b>")
        bot.register_next_step_handler(msg, lambda m: process_admin_op(m, 'del'))
    bot.answer_callback_query(c.id)

def process_admin_op(m, op):
    try:
        tid = int(m.text.strip())
        admins = get_admins()
        if op == 'add':
            if tid not in admins: admins.append(tid)
            msg = f"✅ 已添加"
        else:
            if str(tid) == str(SUPER_ADMIN_ID): msg = "❌ 不能移除超级管理员"
            elif tid in admins: admins.remove(tid); msg = f"✅ 已移除"
            else: msg = "⚠️ 未找到"
        save_admins(admins)
        bot.send_message(m.chat.id, msg)
    except: pass

@bot.message_handler(regexp='🛠️ 实用工具')
def util_menu(m):
    mk = types.InlineKeyboardMarkup()
    mk.add(types.InlineKeyboardButton("⚡ Speedtest", callback_data='tool_speedtest'),
           types.InlineKeyboardButton("☁️ 备份配置", callback_data='tool_backup'))
    bot.send_message(m.chat.id, "🛠️ <b>工具箱</b>", reply_markup=mk)

def handle_tools(c):
    bot.answer_callback_query(c.id, "执行中...")
    if 'speedtest' in c.data:
        bot.send_message(c.message.chat.id, "⏳ 正在测速...")
        ok, res = execute_command("speedtest-cli --simple")
        bot.send_message(c.message.chat.id, f"⚡ <b>测速结果:</b>\n<pre>{html.escape(res)}</pre>")
    elif 'backup' in c.data:
        if os.path.exists(XRAY_CONF):
            bot.send_document(c.message.chat.id, open(XRAY_CONF, 'rb'), caption="📜 Xray Config")

if __name__ == '__main__':
    print("🚀 Bot V6 Final Started...")
    bot.polling(none_stop=True)
EOF_BOT
chmod +x "$BOT_SCRIPT"
green "✅ 机器人代码生成完毕。"

# --- 5. Restart Service ---
green "🛠️ 重启服务..."
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

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl restart ${SERVICE_NAME}.service

echo ""
green "🎉 部署全部完成！已启用 HTML 模式和二维码功能。"
echo "请在 Telegram 中发送 /menu 体验最终版本。"
