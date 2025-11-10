<h1 align="center">🚀 nlbwvpn — 一键部署 VLESS + WS + TLS + Telegram 推送</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Author-nlbw-blueviolet?style=for-the-badge">
  <img src="https://img.shields.io/badge/Built%20With-Bash-green?style=for-the-badge&logo=gnu-bash">
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge">
  <img src="https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-orange?style=for-the-badge&logo=linux">
</p>

<p align="center">
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh">
    <img src="https://img.shields.io/badge/💾%20立即安装-nlbwvpn.sh-red?style=for-the-badge">
  </a>
</p>

---

## ✨ 项目简介

**`nlbwvpn`** 是一个全自动化的 VPN 部署脚本，专为个人 VPS 打造。  
支持 **VLESS + WS + TLS** 协议，并通过 Telegram 自动发送链接和二维码。  
一键安装，无需手动配置 Xray / Nginx / 证书 / BBR。

---

## 🧠 功能亮点

✅ 自动安装 Xray（VLESS + WS + TLS）  
✅ 自动申请 Let’s Encrypt 证书  
✅ 自动生成 VLESS 链接与二维码  
✅ 自动推送到 Telegram 私聊  
✅ 自动健康检测 + 周报  
✅ 启用 BBR 加速  
✅ 一键复制命令即可运行  

---

## 🚀 一键部署命令

```bash
sudo -i
bash <(curl -Ls https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh)

⚠️ 请确保域名已正确解析至 VPS 公网 IP！
⚙️ 执行时交互参数
参数	示例	说明
域名	090110.xyz	必须已解析到 VPS
邮箱	admin@gmail.com
	用于签发证书
Telegram Bot Token	123456789:ABC...	从 @BotFather 获取
Telegram Chat ID	123456789	用 @userinfobot 查询
健康检测间隔	300	每 300 秒检测 nginx/xray 状态
📦 部署结果

成功后脚本将：

自动生成 VLESS 链接

保存二维码至 /root/vless-qrcode.png

发送 Telegram 通知（含二维码与链接）

示例输出：
🎉 部署完成！
VLESS 链接:
vless://UUID@090110.xyz:443?encryption=none&security=tls&type=ws&host=xjp.090110.xyz&path=%2Fws#xjp.090110.xyz

📊 自动健康与报告系统
功能	systemd 服务名	周期
实时健康检测	tg-control.service	每间隔秒检测 nginx/xray
BBR 状态检查	bbr-status.timer	每周运行一次
Telegram 周报	bbr-weekly-report.timer	每周一 03:10 发送报告
🗂️ 关键文件路径
文件路径	说明
/root/deploy.log	部署日志
/root/vless-qrcode.png	二维码
/usr/local/etc/xray/config.json	Xray 配置文件
/var/log/bbr-check.log	BBR 检测日志
💡 常见问题（FAQ）

Q1：Certbot 申请失败？
→ 确认域名的 A 记录已正确指向 VPS 公网 IP。

Q2：Telegram 没收到消息？
→ 确认 Chat ID 正确（纯数字），并且你已主动与 Bot 开启私聊。

Q3：脚本能重复运行吗？
→ ✅ 可以安全重复运行，会覆盖更新配置，不影响现有服务。

🧰 系统要求

Debian 10 / 11 / 12

Ubuntu 20.04 / 22.04 / 24.04

Root 权限

已配置解析的域名

🧑‍💻 作者与支持

作者：nlbw
📧 Email: hupan0210@gmail.com

🌐 项目主页: https://github.com/Hupan0210/vpn

⚖️ License

本项目基于 MIT License
 开源。
欢迎 Fork、修改、提交 PR 或开 Issue 一起完善！

