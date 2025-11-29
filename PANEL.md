# 🖥️ nlbw-panel — 极简主义 Xray Web 控制台

<p align="center">
  <a href="https://github.com/Hupan0210/vpn"><img src="https://img.shields.io/badge/Version-V3.0-blue?style=flat-square" /></a>
  <a href="https://flask.palletsprojects.com/"><img src="https://img.shields.io/badge/Python-Flask-green?style=flat-square&logo=python" /></a>
  <a href="https://www.apple.com/"><img src="https://img.shields.io/badge/Design-Apple%20UI-white?style=flat-square&logo=apple" /></a>
</p>

<p align="center"><strong>专为极客打造的“隐形”服务器管理系统</strong><br>单文件部署 • 极简伪装 • 全能管理 • 实时监控</p>

<p align="center">
  <a href="#-功能特性">✨ 功能特性</a> •
  <a href="#-一键部署">🚀 一键部署</a> •
  <a href="#🕵️‍♂️-如何进入后台">🕵️‍♂️ 如何进入后台</a> •
  <a href="#-技术栈">🛠️ 技术栈</a>
</p>

---

## ✨ 功能特性

**nlbw-panel** 是一款极简、轻量、安全的 Web 控制台，用于管理 Xray 全套服务。

### 🛡️ 隐蔽与安全

* **工程风伪装页面**：默认展示 “Under Construction” 无害页面。
* **隐形后台入口**：登录入口藏在页面最底部的年份里。
* **安全会话控制**：基于 Flask-Login 的安全鉴权。

### 📊 全能控制台

* **实时仪表盘**：CPU / 内存 / 磁盘 / 流量 的动态监控。
* **节点管理**：新增 / 删除 / 修改 VLESS 与 Socks5 用户。
* **二维码生成**：网页直接生成扫码连接二维码。
* **TG 管理**：在线增删 Telegram 管理员。
* **文件管理器**：在线编辑 `config.json`、HTML 等配置文件。
* **黑匣子日志**：实时查看 Xray 运行日志。
* **工具箱**：测速 / 备份 等常用运维工具。

---

## 🚀 一键部署

使用 Root 身份运行以下脚本：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/Hupan0210/vpn/main/panel.sh)
```

运行后脚本会提示设置后台 **管理员账号与密码**，务必保存好。

---

## 🕵️‍♂️ 如何进入后台

为了最大限度隐藏后台入口，首页不会出现任何“Login”按钮。

1. **访问首页**：打开你绑定的域名，例如 `https://vpn.example.com`。
2. **滑到底部**：找到页面最底部的版权信息。
3. **点击年份“2025”**：隐形入口机关被触发。
4. **输入账号密码**：弹出磨砂玻璃风格的登录框。

登录成功后即可进入全能控制台。

---

## 🛠️ 技术栈

* **后端**：Python 3 + Flask
* **前端**：原生 JavaScript + CSS3（无框架）
* **监控采集**：psutil
* **反向代理**：Nginx（转发 `/api`）

---

## 📂 目录结构

```
/usr/local/bin/
└── nlbw_panel.py        # 后端核心逻辑

/var/www/[域名]/html/
├── index.html           # 伪装首页（包含暗门）
└── admin.html           # 控制台前端

/etc/systemd/system/
└── nlbw-panel.service   # 后台守护进程
```

---

<p align="center"> Built with ❤️ by <a href="https://github.com/hupan0210">Hupan0210</a> </p>
