#!/usr/bin/env bash
#
# panel.sh - NLBW Web Dashboard (Final Verified)
# Fixes: Backup API, Nginx Path Detection, ID Consistency
#

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Colors ---
green(){ echo -e "\033[1;32m$1\033[0m"; }
red(){ echo -e "\033[1;31m$1\033[0m"; }
yellow(){ echo -e "\033[1;33m$1\033[0m"; }

# --- Global Vars ---
PANEL_SCRIPT="/usr/local/bin/nlbw_panel.py"
SERVICE_NAME="nlbw-panel"
CONFIG_ENV="/etc/nlbwvpn/config.env"

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
    red "❌ 错误: 必须使用 root 权限运行此脚本。"
    exit 1
fi

green "🚀 启动 Web 超级面板部署 (修复版)..."

# ==============================================================================
# 1. 交互配置 & 基础检查
# ==============================================================================

# 确保配置目录存在
mkdir -p /etc/nlbwvpn

# 尝试自动读取域名
AUTO_DOMAIN=""
if [[ -f "$CONFIG_ENV" ]]; then
    # 使用 grep 提取，避免 source 可能的环境污染
    AUTO_DOMAIN=$(grep '^DOMAIN=' "$CONFIG_ENV" | cut -d= -f2 | tr -d '"')
fi

echo "----------------------------------------------------"
echo "🛠️  后台安全设置"
echo "----------------------------------------------------"

while true; do
    read -r -p "请输入域名 [默认: ${AUTO_DOMAIN}]: " INPUT_DOMAIN
    FINAL_DOMAIN=${INPUT_DOMAIN:-$AUTO_DOMAIN}
    if [[ -n "$FINAL_DOMAIN" ]]; then break; fi
    red "域名不能为空！"
done

read -r -p "设置后台账号 [默认: admin]: " PANEL_USER
PANEL_USER=${PANEL_USER:-admin}

while true; do
    read -r -p "设置后台密码 (必填): " PANEL_PASS
    if [[ -n "$PANEL_PASS" ]]; then break; fi
    red "密码不能为空！"
done

# ==============================================================================
# 2. 安装依赖
# ==============================================================================
green "📦 安装系统依赖..."
apt-get update -y
apt-get install -y python3 python3-pip speedtest-cli zip

green "⬇️ 安装 Python 库 (Flask, Psutil)..."
pip3 install flask flask-login psutil --break-system-packages --ignore-installed blinker

# ==============================================================================
# 3. 部署 Python 后端 (含备份功能)
# ==============================================================================
green "🧠 生成后端逻辑 (API)..."

cat << 'EOF' > "$PANEL_SCRIPT"
import os
import subprocess
import json
import psutil
import time
import uuid
import zipfile
import io
from flask import Flask, jsonify, request, send_file
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user

app = Flask(__name__)
app.secret_key = os.urandom(24)

# --- PLACEHOLDERS ---
ADMIN_USER = "PLACEHOLDER_USER"
ADMIN_PASS = "PLACEHOLDER_PASS"
XRAY_CONF = "/usr/local/etc/xray/config.json"
ADMINS_FILE = "/etc/nlbwvpn/admins.json"
XRAY_LOG = "/var/log/xray/access.log"
XRAY_ERR = "/var/log/xray/error.log"

login_manager = LoginManager()
login_manager.init_app(app)

class User(UserMixin):
    def __init__(self, id): self.id = id

@login_manager.user_loader
def load_user(user_id): return User(user_id) if user_id == ADMIN_USER else None

@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    if data.get('username') == ADMIN_USER and data.get('password') == ADMIN_PASS:
        login_user(User(ADMIN_USER))
        return jsonify({"status": "success"})
    return jsonify({"status": "fail"}), 401

def get_json(path, default=[]):
    if not os.path.exists(path): return default
    try:
        with open(path, 'r') as f: return json.load(f)
    except: return default

def save_json(path, data):
    with open(path, 'w') as f: json.dump(data, f, indent=2)

def get_domain():
    try:
        with open("/etc/nlbwvpn/config.env") as f:
            for line in f:
                if line.startswith("DOMAIN="): return line.strip().split('=')[1].strip('"')
    except: pass
    return "Unknown"

# --- Status & Tools ---
@app.route('/api/status')
@login_required
def status():
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    net = psutil.net_io_counters()
    xray = subprocess.run(['systemctl','is-active','xray'], capture_output=True, text=True).stdout.strip()
    nginx = subprocess.run(['systemctl','is-active','nginx'], capture_output=True, text=True).stdout.strip()
    return jsonify({
        "cpu": psutil.cpu_percent(1), "ram": mem.percent, "disk": disk.percent,
        "net_up": net.bytes_sent, "net_down": net.bytes_recv,
        "uptime": int(time.time() - psutil.boot_time()),
        "xray": xray, "nginx": nginx
    })

@app.route('/api/tools/speedtest', methods=['POST'])
@login_required
def run_speedtest():
    try:
        res = subprocess.run("speedtest-cli --simple", shell=True, capture_output=True, text=True)
        return jsonify({"result": res.stdout})
    except Exception as e: return jsonify({"result": str(e)})

@app.route('/api/tools/backup', methods=['GET'])
@login_required
def backup_config():
    # 创建内存中的 ZIP
    memory_file = io.BytesIO()
    with zipfile.ZipFile(memory_file, 'w') as zf:
        if os.path.exists(XRAY_CONF): zf.write(XRAY_CONF, 'xray_config.json')
        if os.path.exists(ADMINS_FILE): zf.write(ADMINS_FILE, 'admins.json')
        if os.path.exists("/etc/nlbwvpn/config.env"): zf.write("/etc/nlbwvpn/config.env", 'config.env')
    memory_file.seek(0)
    return send_file(memory_file, download_name='vpn_backup.zip', as_attachment=True)

@app.route('/api/restart', methods=['POST'])
@login_required
def restart_svc():
    svc = request.json.get('service')
    if svc in ['xray', 'nginx']:
        subprocess.run(f"systemctl restart {svc}", shell=True)
        return jsonify({"status": "success"})
    return jsonify({"error": "Invalid service"}), 400

# --- Users ---
@app.route('/api/users', methods=['GET'])
@login_required
def get_users():
    data = get_json(XRAY_CONF, {})
    domain = get_domain()
    users = []
    inb_v = next((i for i in data.get('inbounds',[]) if i['protocol']=='vless'), None)
    if inb_v:
        path = inb_v['streamSettings']['wsSettings']['path']
        for cl in inb_v['settings']['clients']:
            link = f"vless://{cl['id']}@{domain}:443?encryption=none&security=tls&type=ws&host={domain}&path={path}#{cl.get('email','User')}"
            users.append({"type": "VLESS", "id": cl['id'], "remark": cl.get('email','-'), "link": link})
    inb_s = next((i for i in data.get('inbounds',[]) if i['protocol']=='socks'), None)
    if inb_s:
        port = inb_s['port']
        for ac in inb_s['settings']['accounts']:
            link = f"socks5://{ac['user']}:{ac['pass']}@{domain}:{port}#{ac['user']}"
            users.append({"type": "Socks5", "id": ac['user'], "remark": f"Pass: {ac['pass']}", "link": link})
    return jsonify(users)

@app.route('/api/users/add', methods=['POST'])
@login_required
def add_user():
    req = request.json
    data = get_json(XRAY_CONF, {})
    if req['type'] == 'VLESS':
        inb = next(i for i in data['inbounds'] if i['protocol']=='vless')
        inb['settings']['clients'].append({"id": str(uuid.uuid4()), "email": req['remark'], "level": 0})
    else:
        inb = next(i for i in data['inbounds'] if i['protocol']=='socks')
        inb['settings']['accounts'].append({"user": req['remark'], "pass": req['password']})
    save_json(XRAY_CONF, data)
    os.chmod(XRAY_CONF, 0o644)
    subprocess.run("systemctl restart xray", shell=True)
    return jsonify({"status": "success"})

@app.route('/api/users/del', methods=['POST'])
@login_required
def del_user():
    req = request.json
    data = get_json(XRAY_CONF, {})
    tgt = req['id']
    if req['type'] == 'VLESS':
        inb = next(i for i in data['inbounds'] if i['protocol']=='vless')
        inb['settings']['clients'] = [c for c in inb['settings']['clients'] if c['id'] != tgt]
    else:
        inb = next(i for i in data['inbounds'] if i['protocol']=='socks')
        inb['settings']['accounts'] = [a for a in inb['settings']['accounts'] if a['user'] != tgt]
    save_json(XRAY_CONF, data)
    os.chmod(XRAY_CONF, 0o644)
    subprocess.run("systemctl restart xray", shell=True)
    return jsonify({"status": "success"})

# --- Admins ---
@app.route('/api/admins', methods=['GET'])
@login_required
def get_admins(): return jsonify(get_json(ADMINS_FILE, []))

@app.route('/api/admins/manage', methods=['POST'])
@login_required
def manage_admins():
    req = request.json
    admins = get_json(ADMINS_FILE, [])
    try:
        uid = int(req['id'])
        if req['action'] == 'add': 
            if uid not in admins: admins.append(uid)
        elif req['action'] == 'del':
            if uid in admins: admins.remove(uid)
        save_json(ADMINS_FILE, admins)
        return jsonify({"status": "success"})
    except: return jsonify({"error": "ID Error"}), 400

# --- Files & Logs ---
@app.route('/api/logs', methods=['GET'])
@login_required
def get_logs():
    lines = []
    if os.path.exists(XRAY_LOG):
        lines.append("=== Access Log (Last 20) ===\n")
        lines.append(subprocess.check_output(['tail', '-n', '20', XRAY_LOG]).decode())
    if os.path.exists(XRAY_ERR):
        lines.append("\n=== Error Log (Last 20) ===\n")
        lines.append(subprocess.check_output(['tail', '-n', '20', XRAY_ERR]).decode())
    return jsonify({"content": "".join(lines)})

@app.route('/api/files', methods=['GET'])
@login_required
def list_files():
    path = request.args.get('path', '/etc/nlbwvpn')
    if not os.path.isdir(path): return jsonify({"error": "Not a dir"}), 400
    items = []
    for f in os.listdir(path):
        full = os.path.join(path, f)
        items.append({"name": f, "type": "dir" if os.path.isdir(full) else "file", "path": full})
    items.sort(key=lambda x: (x['type']!='dir', x['name']))
    return jsonify({"current": path, "items": items})

@app.route('/api/read_file', methods=['POST'])
@login_required
def read_file():
    try:
        with open(request.json['path'], 'r', errors='ignore') as f: return jsonify({"content": f.read()})
    except: return jsonify({"error": "Read fail"}), 500

@app.route('/api/save_file', methods=['POST'])
@login_required
def save_file():
    try:
        with open(request.json['path'], 'w') as f: f.write(request.json['content'])
        return jsonify({"status": "success"})
    except: return jsonify({"error": "Save fail"}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

# 替换账号密码
sed -i "s/PLACEHOLDER_USER/$PANEL_USER/g" "$PANEL_SCRIPT"
sed -i "s/PLACEHOLDER_PASS/$PANEL_PASS/g" "$PANEL_SCRIPT"

# 注册服务
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF_SVC
[Unit]
Description=NLBW Web Panel Backend
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${PANEL_SCRIPT}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF_SVC

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

# ==============================================================================
# 4. 部署前端 (伪装 + 控制台)
# ==============================================================================
green "🎨 部署前端页面..."
WEB_ROOT="/var/www/${FINAL_DOMAIN}/html"
mkdir -p "$WEB_ROOT"

# 4.1 伪装首页 (Camouflage)
cat << 'EOF' > "$WEB_ROOT/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Maintenance</title>
    <style>
        body { background: #f0f2f5; font-family: 'Courier New', monospace; display: flex; flex-direction: column; justify-content: center; align-items: center; height: 100vh; margin: 0; color: #333; }
        .container { text-align: center; padding: 40px; border: 2px dashed #ccc; border-radius: 8px; background: #fff; max-width: 400px; }
        .icon { width: 64px; height: 64px; margin-bottom: 20px; fill: #e67e22; }
        h1 { font-size: 20px; margin-bottom: 10px; text-transform: uppercase; }
        p { font-size: 14px; color: #666; margin-bottom: 30px; }
        .btn { padding: 10px 20px; background: #24292e; color: #fff; text-decoration: none; border-radius: 4px; font-size: 14px; font-weight: bold; }
        .footer { margin-top: 40px; font-size: 12px; color: #999; }
        .hidden-link { text-decoration: none; color: inherit; cursor: text; }
    </style>
</head>
<body>
    <div class="container">
        <svg class="icon" viewBox="0 0 24 24"><path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.06-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.74,8.87 C2.62,9.08,2.66,9.34,2.86,9.49l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.06,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.44-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.47-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/></svg>
        <h1>Under Construction</h1>
        <p>System update in progress.</p>
        <a href="javascript:void(0)" class="btn">Learn More</a>
        <div class="footer">&copy; <a href="/admin.html" class="hidden-link">2025</a> Inc.</div>
    </div>
</body>
</html>
EOF

# 4.2 超级控制台 (Admin Panel)
cat << 'EOF' > "$WEB_ROOT/admin.html"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN 控制中心</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
    <style>
        :root{--bg:#f5f5f7;--sidebar:#fff;--card:#fff;--text:#1d1d1f;--accent:#0071e3;--danger:#ff3b30}
        @media(prefers-color-scheme:dark){:root{--bg:#1c1c1e;--sidebar:#2c2c2e;--card:#2c2c2e;--text:#f5f5f7}}
        body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Microsoft YaHei",sans-serif;background:var(--bg);color:var(--text);display:flex;height:100vh;overflow:hidden}
        #login-layer{position:fixed;inset:0;background:var(--bg);z-index:999;display:flex;justify-content:center;align-items:center}
        .box{background:var(--card);padding:40px;border-radius:20px;box-shadow:0 10px 40px rgba(0,0,0,0.1);width:300px;text-align:center}
        input,select{width:100%;padding:12px;margin:10px 0;border:1px solid #ccc;border-radius:8px;box-sizing:border-box;background:var(--bg);color:var(--text)}
        button{padding:10px 20px;background:var(--accent);color:#fff;border:none;border-radius:8px;cursor:pointer;font-weight:600}
        button.danger{background:var(--danger)}
        button.sm{padding:6px 12px;font-size:12px}
        .sidebar{width:220px;background:var(--sidebar);border-right:1px solid rgba(128,128,128,0.1);display:flex;flex-direction:column;padding:20px}
        .nav-item{padding:12px 15px;margin-bottom:5px;cursor:pointer;border-radius:10px;opacity:0.7}
        .nav-item:hover,.nav-item.active{background:var(--accent);color:#fff;opacity:1}
        .main{flex:1;padding:30px;overflow-y:auto;display:none;flex-direction:column;gap:20px}
        .card{background:var(--card);padding:25px;border-radius:18px;box-shadow:0 2px 10px rgba(0,0,0,0.02)}
        .grid-4{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:20px}
        .stat-val{font-size:28px;font-weight:700;color:var(--accent);margin-top:5px}
        table{width:100%;border-collapse:collapse;margin-top:10px}
        th,td{text-align:left;padding:15px;border-bottom:1px solid rgba(128,128,128,0.1)}
        .modal{position:fixed;inset:0;background:rgba(0,0,0,0.4);backdrop-filter:blur(5px);display:none;justify-content:center;align-items:center;z-index:100}
        .modal-content{background:var(--card);padding:30px;border-radius:16px;width:400px;max-width:90%}
    </style>
</head>
<body>
    <div id="login-layer"><div class="box"><h3>后台管理</h3><input type="text" id="u" placeholder="用户名"><input type="password" id="p" placeholder="密码"><button onclick="login()" style="width:100%">登录</button></div></div>
    <div class="sidebar" id="sidebar" style="display:none">
        <h2>控制中心</h2>
        <div class="nav-item active" onclick="tab('dash')">📊 系统概览</div>
        <div class="nav-item" onclick="tab('users')">👥 节点管理</div>
        <div class="nav-item" onclick="tab('admins')">👮 TG 管理员</div>
        <div class="nav-item" onclick="tab('files')">📂 文件管理</div>
        <div class="nav-item" onclick="tab('logs')">📝 运行日志</div>
        <div class="nav-item" onclick="tab('tools')">🛠️ 实用工具</div>
        <div style="flex:1"></div><div class="nav-item" style="color:#ff3b30" onclick="location.reload()">🔒 退出</div>
    </div>
    <div class="main" id="view-dash"><h1>系统概览</h1><div class="grid-4"><div class="card">CPU<div class="stat-val" id="cpu">-</div></div><div class="card">内存<div class="stat-val" id="ram">-</div></div><div class="card">磁盘<div class="stat-val" id="disk">-</div></div><div class="card">运行<div class="stat-val" id="uptime">-</div></div></div></div>
    <div class="main" id="view-users">
        <div style="display:flex;justify-content:space-between"><h1>节点管理</h1><div><button onclick="addM('VLESS')">+ VLESS</button> <button onclick="addM('Socks5')">+ Socks5</button></div></div>
        <div class="card"><table><thead><tr><th>类型</th><th>ID/账号</th><th>备注/密码</th><th>操作</th></tr></thead><tbody id="ulist"></tbody></table></div>
    </div>
    <div class="main" id="view-admins"><h1>TG 管理员</h1><div class="card"><input type="number" id="aid" placeholder="ID" style="width:150px;display:inline-block"><button onclick="manAdm('add')">添加</button><table><tbody id="alist"></tbody></table></div></div>
    <div class="main" id="view-files"><h1>文件管理 <span id="path" style="font-size:12px;opacity:0.5"></span></h1><div style="margin-bottom:10px"><button class="sm" onclick="loadDir('/etc/nlbwvpn')">配置</button> <button class="sm" onclick="loadDir('/var/www')">网站</button></div><div class="card"><ul id="flist" style="list-style:none;padding:0"></ul></div></div>
    <div class="main" id="view-logs"><h1>日志</h1><button class="sm" onclick="loadLogs()">刷新</button><pre id="lview" style="background:#1e1e1e;color:#0f0;padding:15px;border-radius:12px;height:400px;overflow:auto"></pre></div>
    
    <div class="main" id="view-tools">
        <h1>工具箱</h1>
        <div class="grid-4">
            <div class="card"><h3>配置备份</h3><p>下载配置压缩包</p><button onclick="window.location.href='/api/tools/backup'">📥 下载备份</button></div>
            <div class="card"><h3>网络测速</h3><p>测试服务器带宽</p><button onclick="speed()">🚀 开始测速</button><pre id="sres" style="margin-top:10px"></pre></div>
        </div>
    </div>
    
    <div id="add-modal" class="modal"><div class="modal-content"><h3>新增用户</h3><input type="hidden" id="ntype"><input id="nrem" placeholder="备注/用户"><input id="npass" placeholder="密码" style="display:none"><div style="margin-top:20px;text-align:right"><button class="sm" style="background:#666" onclick="closeM('add-modal')">取消</button> <button class="sm" onclick="subUser()">确定</button></div></div></div>
    <div id="qr-modal" class="modal"><div class="modal-content" style="text-align:center"><div id="qrcode" style="display:flex;justify-content:center;margin:20px 0"></div><input id="qlink" readonly onclick="this.select()"><button class="sm" onclick="closeM('qr-modal')" style="margin-top:10px">关闭</button></div></div>
    
    <script>
        async function login(){
            const u=document.getElementById('u').value,p=document.getElementById('p').value;
            const res=await fetch('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username:u,password:p})});
            if(res.ok){document.getElementById('login-layer').style.display='none';document.getElementById('sidebar').style.display='flex';tab('dash');ref();setInterval(ref,3000);}else alert('失败');
        }
        function tab(id){document.querySelectorAll('.main').forEach(e=>e.style.display='none');document.querySelectorAll('.nav-item').forEach(e=>e.classList.remove('active'));document.getElementById('view-'+id).style.display='flex';if(id==='users')loadU();if(id==='admins')loadA();if(id==='files')loadDir('/etc/nlbwvpn');if(id==='logs')loadLogs();}
        async function ref(){if(document.getElementById('view-dash').style.display==='none')return;const d=await(await fetch('/api/status')).json();document.getElementById('cpu').innerText=d.cpu+'%';document.getElementById('ram').innerText=d.ram+'%';document.getElementById('disk').innerText=d.disk+'%';document.getElementById('uptime').innerText=Math.floor(d.uptime/3600)+'h';}
        async function loadU(){const d=await(await fetch('/api/users')).json();const t=document.getElementById('ulist');t.innerHTML='';d.forEach(u=>{t.innerHTML+=`<tr><td>${u.type}</td><td style="font-size:12px">${u.id}</td><td>${u.remark}</td><td><button class="sm" onclick="qr('${u.link}')">码</button> <button class="sm danger" onclick="del('${u.id}','${u.type}')">删</button></td></tr>`});}
        function qr(l){document.getElementById('qr-modal').style.display='flex';document.getElementById('qrcode').innerHTML='';new QRCode(document.getElementById("qrcode"),{text:l,width:200,height:200});document.getElementById('qlink').value=l;}
        function addM(t){document.getElementById('add-modal').style.display='flex';document.getElementById('ntype').value=t;document.getElementById('npass').style.display=t==='Socks5'?'block':'none';}
        async function subUser(){const t=document.getElementById('ntype').value,r=document.getElementById('nrem').value,p=document.getElementById('npass').value;await fetch('/api/users/add',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({type:t,remark:r,password:p})});closeM('add-modal');loadU();}
        async function del(i,t){if(!confirm('删?'))return;await fetch('/api/users/del',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:i,type:t})});loadU();}
        async function loadA(){const d=await(await fetch('/api/admins')).json();const t=document.getElementById('alist');t.innerHTML='';d.forEach(i=>{t.innerHTML+=`<tr><td>${i}</td><td>管理员</td><td><button class="sm danger" onclick="manAdm('del',${i})">删</button></td></tr>`});}
        async function manAdm(a,i=null){const t=i||document.getElementById('aid').value;if(!t)return;await fetch('/api/admins/manage',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:a,id:t})});loadA();}
        async function loadDir(p){const d=await(await fetch(`/api/files?path=${p}`)).json();if(d.error)return;document.getElementById('path').innerText=p;const t=document.getElementById('flist');t.innerHTML='';if(p!=='/')t.innerHTML+=`<li onclick="loadDir('${p.substring(0,p.lastIndexOf('/'))||'/'}')"><span>📁 ..</span></li>`;d.items.forEach(i=>{t.innerHTML+=`<li><span>${i.type==='dir'?'📁':'📄'} ${i.name}</span></li>`});}
        async function loadLogs(){const d=await(await fetch('/api/logs')).json();document.getElementById('lview').innerText=d.content;}
        async function speed(){document.getElementById('sres').innerText='测速中...';const d=await(await fetch('/api/tools/speedtest',{method:'POST'})).json();document.getElementById('sres').innerText=d.result;}
        function closeM(i){document.getElementById(i).style.display='none';}
    </script>
</body>
</html>
EOF

chown -R www-data:www-data "$WEB_ROOT"

# ==============================================================================
# 5. 配置 Nginx 反代 (智能识别配置)
# ==============================================================================
green "🔧 配置 Nginx 接口转发..."

# 查找 Nginx 配置文件 (模糊匹配域名，防止文件名差异)
NGINX_CONF=$(find /etc/nginx/sites-available -name "*${FINAL_DOMAIN}*.conf" | head -n 1)

if [[ -n "$NGINX_CONF" ]]; then
    if ! grep -q "location /api/" "$NGINX_CONF"; then
        sed -i '/location \/ {/i \    location /api/ {\n        proxy_pass http://127.0.0.1:5000;\n    }\n' "$NGINX_CONF"
        systemctl restart nginx
        green "✅ Nginx 转发规则已添加至: $NGINX_CONF"
    else
        yellow "⚠️ Nginx 规则已存在，跳过"
    fi
else
    red "❌ 未找到域名的 Nginx 配置文件！请检查核心服务是否安装正确。"
    echo "尝试手动查找: ls /etc/nginx/sites-available/"
fi

# ==============================================================================
# 6. 完成
# ==============================================================================
echo ""
green "🎉 部署全部完成！"
echo "----------------------------------------------------"
echo "🌐 访问地址: https://${FINAL_DOMAIN}/"
echo "🕵️‍♂️ 隐藏入口: 点击页面底部的 '2025' 字样"
echo "👤 后台账号: $PANEL_USER"
echo "🔑 后台密码: $PANEL_PASS"
echo "----------------------------------------------------"
