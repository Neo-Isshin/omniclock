<div align="center">

**简体中文** · [English](README.md)

# 🕰️ OmniClock

**把 AI 用量、订阅额度、资讯、提醒和实用工具，放到桌面上。**

[![下载](https://img.shields.io/badge/Downloads-GitHub-10B981?style=for-the-badge)](https://github.com/Neo-Isshin/omniclock/releases/latest)
[![macOS 12+](https://img.shields.io/badge/macOS-12%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](#支持平台)
[![Liquid Glass](https://img.shields.io/badge/macOS%2026%2B-Liquid%20Glass-00B0F0?style=for-the-badge&logo=apple&logoColor=white)](#支持平台)
[![Windows](https://img.shields.io/badge/Windows-11-0078D4?style=for-the-badge)](#windows)
[![Linux](https://img.shields.io/badge/Linux-GTK3%20AppImage-FCC624?style=for-the-badge&logo=linux&logoColor=black)](#支持平台)

[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![MIT 许可](https://img.shields.io/badge/License-MIT-3B82F6.svg)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/Neo-Isshin/omniclock?style=social)](https://github.com/Neo-Isshin/omniclock)

</div>

<div align="center">
<table>
  <tr>
    <td align="center" valign="bottom"><img src="docs/screenshots/glass_zh.png" alt="Liquid Glass 表盘" width="220"><br><sub><b>Liquid Glass</b><br>一眼掌握桌面概览</sub></td>
    <td align="center" valign="bottom"><img src="docs/screenshots/dropdown_zh.png" alt="用量详情" width="230"><br><sub><b>用量详情</b><br>工具、会话与模型</sub></td>
    <td align="center" valign="bottom"><img src="docs/screenshots/normal_zh.png" alt="Normal 版表盘" width="220"><br><sub><b>Normal</b><br>适配主题的原生界面</sub></td>
  </tr>
</table>
</div>

---

**OmniClock** 原名 **TokenClock**，将日常使用 AI 时关心的信息和工具集中到桌面。表盘展示活动与选定额度，展开后可以查看用量历史、费用、行事本、AI 资讯，以及本地和网络诊断工具。

**OmniClock v1.0.0** 同时提供 macOS Glass、macOS Normal、Windows 和 Linux 版本。仓库保留原有历史；macOS／Linux 使用 `omniclock` 主命令，原来的 `tokenclock` 命令、设置与用量历史继续兼容。

## 功能

| 区域 | 可以做什么 |
|---|---|
| **桌面概览** | 查看今日 Token、消息数、活跃工具、天气与订阅额度环；选择表盘、尺寸及是否始终置顶。 |
| **用量与 API 等价费用** | 按工具、会话或模型展开，切换缓存读取口径，查看估算费用及支持来源的 Fast／Priority 拆分。近期生成速度每 3 分钟刷新。 |
| **订阅额度** | 查看支持的账号、剩余额度与重置时间。最多选择 4 个工具，每次显示 2 个。对已获取或手动填写的续费日期，可设置提前 1、2、3、7 天提醒。 |
| **历史与分享** | 查看近 30 天或自选日期范围；起止日期为同一天时显示每小时用量。按单日、近几天、月份或自然周导出分享图片，可选是否包含缓存读取及图片背景。 |
| **AI 速递与行事本** | 阅读带厂商 logo 和分类标签的 Ailyre 资讯，记录简单文字并设置提醒。资讯每 2 小时刷新，应用版本每 12 小时检查一次。 |
| **网络工具箱** | 点击后检测 DNS／DoH、WebRTC、IPv6、出口 IP 与地区、AI 域名分流，以及大陆可达性参考；区分可能有风险与尚不能确认的结果。 |
| **本地工具箱与模型检测** | 检查环境冲突和磁盘占用，本地扫描日志泄密，检查时钟偏差，并以脱敏结果验证配置中的 API Key。模型检测分析已有会话证据，也支持用户明确启动的外部检查。 |

macOS 和 Windows 的总结面板集中展示小时用量、较昨日同期、缓存利用率、额度重置时间、行事本和工具／模型列表。快捷按钮可以调整显示与顺序。Linux 通过原生菜单和面板提供对应功能，部分检查会打开浏览器。

## 支持平台

| 平台 | 版本 | 当前分发情况 |
|---|---|---|
| macOS 26+ | Glass 或 Normal | v1.0.0，Apple 芯片／Intel 通用包 |
| macOS 12–25 | Normal | v1.0.0 通用包，不透明主题表盘 |
| Linux x86_64 | Normal，GTK3／Cairo | v1.0.0 AppImage，要求 glibc 2.35+；缺少 FUSE 时可解包运行 |
| Windows 11 x86_64 | Normal，Win32 | v1.0.0 便携包；原生 Acrylic 毛玻璃面板与系统回退样式 |

Glass 保留透明材质与专属光学效果，Normal 使用自己的主题和对比度规则。Normal 的 **Text Color／字体颜色** 快捷按钮只影响详情面板，表盘文字有独立的外观设置。

四个版本对齐共享统计、价格、历史与发布版本。Windows 使用 Win32／WebView2 和原生 Acrylic；Linux 保留 GTK 面板，浏览器 DNS／WebRTC 泄漏项目在 Ailyre 完整检测页运行。项目测试在本机或自有测试机进行，不使用 GitHub Actions。

## 安装

### macOS 与 Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.sh | bash
```

安装器会选择支持的版本、校验安装包，并同时安装两个命令：

```bash
omniclock doctor
omniclock start --normal
omniclock restart
omniclock update
omniclock update --check
```

`update --check` 只下载当前安装脚本，不执行安装或重启。需要指定 macOS 版本时可添加 `--glass` 或 `--normal`。`omniclock uninstall` 移除已安装的 runtime，保留 CLI 命令供以后重装。

#### 已安装 TokenClock 的用户

原来的命令仍然有效：

```bash
tokenclock update
# CLI 更新后，两个名字均可使用：
omniclock doctor
tokenclock doctor
```

新安装器将 `omniclock` 作为主实现，`tokenclock` 作为参数转发入口。两者使用同一份安装与设置。现有 `TOKENCLOCK_*` 环境变量、`~/.tokenclock`、应用标识及可执行文件名称继续兼容，无需维护两份用量历史。

原来的 `https://www.ailyre.com/tokenclock/install.sh` 地址继续可用。如果从仓库手动安装 CLI，请将两个脚本一起放到 `PATH` 中的同一目录。

macOS 可能要求授权访问受保护目录或外接磁盘。当前临时签名安装包不保证二进制更新后能够沿用全部授权。

### Windows

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.ps1)))
```

为当前用户安装已验证的 Windows v1.0.0 包，并校验 SHA-256。为兼容既有安装，目录与可执行文件仍保留 TokenClock 名称。上面的 `omniclock`／`tokenclock` Shell 管理命令适用于 macOS 和 Linux。

<details>
<summary>Windows 安装器选项</summary>

```powershell
# 安装后不立即启动，可选创建开始菜单快捷方式。
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.ps1))) -NoStart -StartMenuShortcut

# 查看安装状态。
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.ps1))) -Action Check

# 卸载并保留 Windows 用户设置。
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.ps1))) -Action Uninstall
```

</details>

## 日常操作

- **点击表盘**打开用量详情，展开工具、会话或模型查看各项消耗。
- **第一行快捷按钮**提供工具箱、历史等入口，可在编辑器中调整显示与顺序。
- **切换 AI 速递**后，在下拉面板下半部分阅读资讯；通过返回按钮回到用量视图。
- **打开订阅额度**选择表盘显示的工具及账号。有多组时，左键点击额度环切换下一组；右键打开额度面板。
- **macOS 菜单栏图标单击**打开今日总结，双击临时将表盘置前或隐藏；右键菜单也提供显示／隐藏入口。
- **右键点击表盘**进入常规、外观、数据路径和通知设置，或检查更新、重启。

详情面板支持左右拉伸，通知面板支持两个方向的拉伸。部分非激活 macOS 面板在可拉伸边缘仍可能显示普通箭头，底部拉伸把手继续可用。

## 支持的数据源

当前四个平台版本 覆盖 Codex、Claude Code、Cursor Agent、Grok Bot、Antigravity、OpenClaw、Gemini CLI、Hermes、OpenCode、Qwen Code、Copilot CLI、Grok CLI、Aider、Cline、Continue、ZCode、Kilo Code、Pi、OMP、PiG、DSH、Command Code 和 Freebuff，具体可统计内容取决于工具实际保存的记录。

- 非默认目录和外接磁盘可在 **设置 → 数据源路径**中指定。
- Freebuff 提供的是本地已完成回复数，不是 Token 记录；这些计数不参与 Token 和 API 等价费用汇总。
- 对只有云端聊天、没有真实 Token 记录的活动，不编造用量估算。
- 只有来源提供合适的时间证据时才展示 t/s 和 TTFT，缺失数据保持不可用。
- 额度卡片复用已有额度记录或允许读取的登录状态；部分账号需要用户主动连接或授权。只有确认共享订阅时才进行去重。

更多细节见[新增 harness](docs/ADDITIONAL_HARNESSES.md)、[小时历史](docs/HOURLY_HISTORY.md)和[订阅周期](docs/SUBSCRIPTION_BILLING.md)。

## 统计口径与隐私

主 Token 数默认不包含缓存读取，可以手动切换。缓存写入、输出和推理遵循数据源实际记录的口径。API 等价费用来自 [Ailyre 价格目录](https://www.ailyre.com/prices/tokenclock.json)，支持用户覆盖价格；它是公开 API 牌价下的估算，**不是订阅实际账单**。

用量采集只读本地日志和数据库，不修改 harness 的记录。额度、天气、资讯和用户启动的网络检查会访问对应服务。本地日志泄密扫描不上传日志；API Key 验活只向配对的配置端点发送凭据，结果脱敏展示。外部模型检测需要确认范围与费用，结果属于证据，不能作为模型身份的证明。

一次网络探测成功不代表所有应用或路由均无泄漏。大陆可达性结果仅供参考，不会把普通超时直接判定为 GFW 封锁。

## 本地 API

启用后，只读 HTTP API 绑定回环地址：

```bash
curl http://127.0.0.1:9988/api/usage
curl 'http://127.0.0.1:9988/api/history?days=30'
```

端口可以配置。API 等价费用带有 `costBasis: "api_equivalent_public_list"` 标记。

## 界面截图

<div align="center">
<p><img src="docs/screenshots/usage_overview.png" alt="用量历史" width="780"></p>
<table>
  <tr>
    <td align="center"><img src="docs/screenshots/subscription_quota.png" alt="订阅额度面板" width="460"></td>
    <td align="center"><img src="docs/screenshots/themes_zh.png" alt="表盘主题选择" width="280"></td>
  </tr>
</table>
</div>

## 开发与帮助

```bash
git clone https://github.com/Neo-Isshin/omniclock.git
cd omniclock
```

`main` 为 macOS Glass，`normal` 为 macOS Normal，`codex/linux-theme-parity` 为当前 Linux 版本。内部 Swift target 和 bundle 名称保留 `TokenClock` 以维持兼容。修改共享组件前，请阅读[平台行为约定](PLATFORM_PARITY.md)和[模型检测集成](docs/MODEL_DETECT_INTEGRATION.md)。

安装异常时先运行 `omniclock doctor`。用量缺失时检查所选目录中是否有真实用量记录；额度异常时区分本机记录缺失、读取权限、登录过期和服务端拒绝。

[反馈问题](https://github.com/Neo-Isshin/omniclock/issues) · [Gitea 镜像](https://gitea.nxc8335.cloud/nxc8335/omniclock) · [Ailyre](https://www.ailyre.com/)

友情链接 · [LINUX DO](https://linux.do/)

## 许可与致谢

采用 [MIT 许可](LICENSE)。打包的第三方库和图片保留各自许可及署名。Ailyre 提供资讯、价格目录和网络检测页面；网络工具按界面标注使用 Cloudflare、Google、Globalping 等服务。OmniClock 是独立项目，并非所支持 AI 厂商的官方客户端。
