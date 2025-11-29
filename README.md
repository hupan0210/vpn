<p align="center">
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh" target="_blank">
    <img src="https://img.shields.io/badge/🟢%20一键安装-nlbwvpn-success?style=for-the-badge&logo=gnubash&logoColor=white" alt="一键安装 nlbwvpn">
  </a>
</p>

<h1 align="center">🚀 nlbwvpn — 极致轻量化 VLESS + Socks5 + Telegram 全能面板</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Author-Hupan0210-blueviolet?style=for-the-badge">
  <img src="https://img.shields.io/badge/Built%20With-Bash%20%7C%20Python-green?style=for-the-badge&logo=python">
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge">
  <img src="https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-orange?style=for-the-badge&logo=linux">
</p>

<p align="center">
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh">
    <img src="https://img.shields.io/badge/💾%20核心部署-nlbwvpn.sh-red?style=for-the-badge">
  </a>
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/tg.sh">
    <img src="https://img.shields.io/badge/🤖%20机器人部署-tg.sh-blue?style=for-the-badge">
  </a>
</p>

---

## ✨ 项目简介

**`nlbwvpn`** 是一套专为小内存 VPS 打造的极致性价比 VPN 解决方案。
项目包含两个核心模块：底层 VPN 服务部署脚本与高级 Telegram 管理机器人。
支持 **VLESS (WS+TLS)** 与 **Socks5** 双协议共存，提供全生命周期的用户管理、二维码分享与服务器状态监控。

---

## 🧠 功能亮点

### 🌐 核心服务 (Core)
- ✅ **双协议共存**：VLESS (主协议, 抗干扰) + Socks5 (备用, TG 专用)
- ✅ **自动 HTTPS**：集成 Certbot 自动申请与续签 Let’s Encrypt 证书
- ✅ **隐蔽伪装**：自动配置 Nginx 反向代理，非代理流量回落至伪装页
- ✅ **性能优化**：自动开启 BBR 加速，小内存机器也能跑满带宽
- ✅ **安全加固**：随机生成 WebSocket 路径与端口，防止主动探测

### 🤖 管理面板 (Bot V6 Ultimate)
- ✅ **交互式管理**：全 HTML 模式面板，彻底解决特殊字符报错问题
- ✅ **多用户管理**：一键新增/删除/修改 VLESS 与 Socks5 用户
- ✅ **二维码分享**：直接生成并发送二维码图片，扫码即连
- ✅ **多管理员协作**：支持授权多个 Telegram 账号共同管理服务器
- ✅ **实用工具箱**：集成 Speedtest 网络测速与配置备份导出
- ✅ **详细监控**：实时查看 CPU、内存、磁盘、流量消耗与服务状态

---

## 🚀 快速使用（Usage）

**注意**：在执行前，请先把你的域名的 A 记录指向 VPS 公网 IP 并等待 DNS 生效。

### 第一步：部署核心服务
在终端以 root 身份运行，安装 Xray 与 Nginx：

```bash
# 切换到 root 用户（必要）
sudo -i

# 执行核心安装脚本
bash <(curl -Ls [https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh](https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh))

脚本会交互式询问域名、邮箱等信息。

第二步：部署管理机器人
核心服务安装完成后，运行此脚本部署 Python 管理面板：

# 执行机器人安装脚本 (V6 Ultimate)
bash <(curl -Ls [https://raw.githubusercontent.com/Hupan0210/vpn/main/tg.sh](https://raw.githubusercontent.com/Hupan0210/vpn/main/tg.sh))

脚本会自动安装 Python 环境、依赖库 (Debian 12 兼容) 并注册系统服务。需提供 Bot Token 和 Chat ID。
📦 部署产物（Key Artifacts）
文件/路径描述/usr/local/bin/nlbw_bot.py机器人核心 Python 逻辑 (V6)/etc/nlbwvpn/config.env机器人环境配置文件 (Token/ID)/etc/nlbwvpn/admins.json多管理员权限数据库/usr/local/etc/xray/config.jsonXray 核心配置文件/etc/nginx/sites-available/[DOMAIN].confNginx 站点配置/root/vless-qrcode.png初始管理员二维码图片
📊 自动化系统（Systemd Services）服务名称描述触发机制nlbw-bot.serviceTelegram 管理机器人开机自启，常驻后台监听指令nlbw-monitor.timer健康检测每 5 分钟检测 Xray/Nginx 存活状态nlbw-weekly.timer周报推送每周一发送运行周报与证书状态

🤖 机器人操作指南
安装完成后，向机器人发送 /menu 即可唤出控制面板：

📊 状态：查看详细的服务器资源占用与流量统计。

👥 用户管理：

新增：一键生成 VLESS/Socks5 朋友账号。

管理：修改备注/密码，删除用户，获取独立二维码。

👮 管理员：添加或移除协助管理的 Telegram 账号。

ℹ️ 获取链接：列出当前所有可用节点的链接（包含二维码）。

🛠️ 实用工具：运行测速或下载备份。

💡 常见问题（FAQ）
Q1：如何新增给朋友使用的账号？ A：在机器人面板点击 👥 用户管理 -> ➕ 新增 VLESS/Socks5，按提示输入备注或密码即可。

Q2：机器人点击按钮没反应？ A：V6 版本已切换至 HTML 模式并增加了交互反馈。如果仍无反应，请检查 VPS 网络是否能连接 Telegram API。

Q3：如何修改 WebSocket 路径或主端口？ A：建议使用 nlbwvpn.sh 重新覆盖安装，或手动修改 /usr/local/etc/xray/config.json 后重启服务。

Q4：Certbot 申请失败？ A：请务必确认域名已解析到当前 IP，且 80/443 端口未被防火墙阻断。

🧰 系统兼容性（Requirements）
OS: Debian 10/11/12, Ubuntu 20.04/22.04/24.04

Python: 3.x (脚本自动处理依赖与 PEP 668 限制)

Permissions: Root 权限

Dependencies: curl, jq, openssl, qrencode (自动安装)

🧑‍💻 作者与支持
作者：Hupan0210

Email：hupan0210@gmail.com

项目地址：https://github.com/Hupan0210/vpn

⚖️ License
本项目基于 MIT License 开源。欢迎 Fork、提交 PR 或开 Issue。
