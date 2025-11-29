<p align="center">
  <h1 align="center">🖥️ nlbw-panel — 极简主义 Xray Web 控制台</h1>
</p>

<p align="center">
  <a href="https://github.com/Hupan0210/vpn">
    <img src="https://img.shields.io/badge/Version-V3.0-blue?style=flat-square" alt="Version">
  </a>
  <a href="https://flask.palletsprojects.com/">
    <img src="https://img.shields.io/badge/Python-Flask-green?style=flat-square&logo=python" alt="Flask">
  </a>
  <a href="https://www.apple.com/">
    <img src="https://img.shields.io/badge/Design-Apple%20UI-white?style=flat-square&logo=apple" alt="Apple UI">
  </a>
</p>

<p align="center">
  <strong>专为极客打造的“隐形”服务器管理系统</strong>
  <br>
  单文件部署 • 极简伪装 • 全能管理 • 实时监控
</p>

<p align="center">
  <a href="#-功能特性">✨ 功能特性</a> • 
  <a href="#-一键部署">🚀 一键部署</a> • 
  <a href="#%EF%B8%8F-如何进入后台">🕵️‍♂️ 如何进入后台</a> • 
  <a href="#-技术栈">🛠️ 技术栈</a>
</p>

---

## ✨ 功能特性

本项目是一个轻量级的 Web 单页应用 (SPA)，旨在替代复杂的服务器运维工作。

### 🛡️ 隐蔽与安全
- **工程风伪装**：默认展示为 "Under Construction" (施工中) 页面，人畜无害。
- **隐形入口**：后台登录入口隐藏在页面底部的版权年份中，只有知道的人才能进入。
- **安全鉴权**：基于 Flask-Login 的会话管理，拒绝未授权访问。

### 📊 全能控制台
- **仪表盘**：实时跳动的 CPU、内存、磁盘占用率及流量监控。
- **节点管理**：
  - **增/删/改**：可视化管理 VLESS 和 Socks5 用户。
  - **二维码**：网页端直接生成连接二维码，手机扫码即连。
- **TG 管理员**：在网页上添加/移除 Telegram 机器人的管理员权限。
- **文件管理**：内置 Web 版资源管理器，支持在线编辑配置文件 (`config.json`, `html` 等)。
- **黑匣子**：实时查看 Xray 运行日志与错误日志。
- **工具箱**：集成 Speedtest 网络测速、一键备份配置下载。

---

## 🚀 一键部署

使用 Root 用户运行以下命令即可完成安装（自动配置 Nginx 反代与 Python 环境）：

```bash
bash <(curl -Ls [https://raw.githubusercontent.com/Hupan0210/vpn/main/panel.sh](https://raw.githubusercontent.com/Hupan0210/vpn/main/panel.sh))

安装提示：脚本会交互式引导您设置 后台管理员账号 和 密码，请务必牢记。

🕵️‍♂️ 如何进入后台
为了极致的隐蔽性，我们没有设置显眼的“登录”按钮。

访问首页：在浏览器打开您的域名（例如 https://vpn.example.com）。

寻找暗门：滚动到页面最底部。

触发机关：点击版权信息中的 "2025" 字样。

解锁：此时会弹出磨砂玻璃风格的登录框，输入安装时设置的账号密码即可。

🛠️ 技术栈
后端：Python 3 + Flask (轻量级 API 服务)

前端：原生 JavaScript + CSS3 (无框架，极致加载速度)

监控：Psutil (系统资源采集)

服务器：Nginx (反向代理 /api 流量)

📂 目录结构
Plaintext

/usr/local/bin/
└── nlbw_panel.py      # 后端核心逻辑
/var/www/[域名]/html/
├── index.html         # 伪装首页 (含暗门)
└── admin.html         # 控制台前端代码
/etc/systemd/system/
└── nlbw-panel.service # 守护进程
<p align="center"> Built with ❤️ by <a href="https://www.google.com/search?q=https://github.com/hupan0210">Hupan0210</a> </p>
