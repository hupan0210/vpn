# 🚀 nlbwvpn — 极致轻量化 VLESS + Socks5 + Telegram 全能面板

<p align="center">
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh">
    <img src="https://img.shields.io/badge/🟢%20一键安装-nlbwvpn-success?style=for-the-badge&logo=gnubash&logoColor=white" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Author-Hupan0210-blueviolet?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Built%20With-Bash%20%7C%20Python-green?style=for-the-badge&logo=python" />
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu-orange?style=for-the-badge&logo=linux" />
</p>

<p align="center">
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh">
    <img src="https://img.shields.io/badge/💾%20核心部署-nlbwvpn.sh-red?style=for-the-badge" />
  </a>
  <a href="https://raw.githubusercontent.com/Hupan0210/vpn/main/tg.sh">
    <img src="https://img.shields.io/badge/🤖%20机器人部署-tg.sh-blue?style=for-the-badge" />
  </a>
</p>

---

## ✨ 项目简介

**nlbwvpn** 是专为小内存 VPS 打造的超轻量 VPN / 代理一体化解决方案，包含：

* 底层 VPN 服务部署脚本
* 高级 Telegram 管理机器人（全 HTML 面板）

支持 **VLESS (WS+TLS)** 与 **Socks5** 双协议并存，并具备用户管理、二维码分享、状态监控等全套能力。

---

## 🧠 功能亮点

### 🌐 核心服务 (Core)

* **双协议共存**：VLESS（主协议）+ Socks5（备用）
* **自动 HTTPS**：集成 Certbot，全自动申请/续签证书
* **隐蔽伪装**：自动配置 Nginx 回落页面 + 随机 WS 路径
* **性能调优**：自动开启 BBR，小机型也能发挥最大带宽
* **安全加固**：随机端口 / 路径，降低探测风险

### 🤖 管理面板 (Bot V6 Ultimate)

* **全 HTML 面板**：支持按钮、列表、实时刷新，无乱码
* **多用户管理**：添加、删除、修改、查看二维码
* **二维码分享**：自动生成并发送图片
* **多管理员模式**：可授权多个 Telegram 账号
* **工具箱**：Speedtest、配置备份导出
* **监控信息**：CPU / 内存 / 磁盘 / 流量 / 服务状态

---

## 🚀 快速使用（Usage）

> ⚠️ **安装前，请确保你的域名 A 记录已解析到 VPS IP，并等待生效！**

### **步骤 1：部署核心服务（Xray + Nginx）**

```bash
sudo -i
bash <(curl -Ls https://raw.githubusercontent.com/Hupan0210/vpn/main/nlbwvpn.sh)
```

脚本会询问域名、邮箱等信息。

---

### **步骤 2：部署 Telegram 管理机器人（Python）**

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Hupan0210/vpn/main/tg.sh)
```

安装过程会自动配置 Python 环境并注册系统服务。

你需要准备：

* Bot Token
* 管理员 Chat ID

---

## 📦 部署后的重要文件

| 路径                                         | 描述                 |
| ------------------------------------------ | ------------------ |
| `/usr/local/bin/nlbw_bot.py`               | 机器人核心代码            |
| `/etc/nlbwvpn/config.env`                  | Token & Chat ID 配置 |
| `/etc/nlbwvpn/admins.json`                 | 管理员数据库             |
| `/usr/local/etc/xray/config.json`          | Xray 主配置文件         |
| `/etc/nginx/sites-available/[DOMAIN].conf` | Nginx 站点配置         |
| `/root/vless-qrcode.png`                   | 初始管理员二维码           |

---

## 📊 自动化 Systemd 服务

| 服务名                  | 描述           | 触发     |
| -------------------- | ------------ | ------ |
| `nlbw-bot.service`   | Telegram 机器人 | 开机自启   |
| `nlbw-monitor.timer` | 服务健康检测       | 每 5 分钟 |
| `nlbw-weekly.timer`  | 周报推送         | 每周一    |

---

## 🤖 机器人操作指南

发送 `/menu` 即可打开完整控制界面：

### 可执行的功能：

* **📊 状态面板**（CPU/内存/流量/Xray/Nginx 状态）
* **👥 用户管理**（新增/删除/备注/密码修改/二维码获取）
* **👮 管理员管理**（添加/删除协助管理者）
* **🔗 获取节点链接**（含二维码）
* **🛠️ 工具箱**（测速、备份下载）

---

## 💡 常见问题（FAQ）

### **Q1：如何新增一个给朋友使用的账号？**

进入 **👥 用户管理 → ➕ 新增用户** 即可。

### **Q2：机器人按钮没反应？**

请检查 VPS 是否能连接 Telegram API。

### **Q3：如何修改 WS 路径或端口？**

建议重新执行 `nlbwvpn.sh` 覆盖安装，或手动修改 Xray 配置并重启：

```
systemctl restart xray
```

### **Q4：证书申请失败怎么办？**

请确认：

* 域名已正确解析
* 80 / 443 端口无占用
* 防火墙未阻断流量

---

## 🧰 系统要求

* **系统**：Debian 10/11/12，Ubuntu 20.04/22.04/24.04
* **Python**：3.x（脚本自动处理依赖）
* **权限**：Root
* **依赖**：curl、jq、openssl、qrencode（自动安装）
> 想要 Web 图形化管理？👉 [查看 Web 超级面板部署文档 (PANEL.md)](PANEL.md)
---

## 🧑‍💻 作者

* **Author**：Hupan0210
* **Email**：[hupan0210@gmail.com](mailto:hupan0210@gmail.com)
* **GitHub**：[https://github.com/Hupan0210/vpn](https://github.com/Hupan0210/vpn)

---

⚖️ License
本项目基于 MIT License 开源。欢迎 Fork、提交 PR 或开 Issue。
