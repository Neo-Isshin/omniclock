# OmniClock v1.0.0

OmniClock 将 AI 用量、订阅额度、行事本、资讯和日常诊断工具集中在桌面。四个平台版本在本次发布中一并更新，保留既有设置和用量历史。

- 统一分享图片、导出文件名、窗口与菜单、Model Detect 页面的 OmniClock 品牌显示。
- 网络工具箱统一结果卡片：每项有直观结论，六行可视区域内滚动查看全部结果；DNS 位置在结果收集完成后补查，并提供备用来源。未完成的检测不会被当作“无泄漏”。
- Windows 补齐总结面板、行事本、AI 速递、工具箱、分享、快捷按钮编辑、四额度两组轮播及托盘交互，新增原生 Acrylic 毛玻璃面板。
- macOS Glass/Normal、Windows、Linux 对齐版本、统计口径、价格 catalog 与更新来源；保留各自主题及平台原生交互。Linux 浏览器泄漏项目在 Ailyre 完整检测页运行。
- 修复 Windows 时区、Python 路径与中文环境编码兼容问题；保留只读日志和每三分钟一次的 t/s 刷新。

## 安装和升级

macOS/Linux：`omniclock update`；原来的 `tokenclock update` 仍可用。

Windows：使用 Ailyre 下载页的安装器或便携包。

下载：[ailyre.com/omniclock/releases](https://www.ailyre.com/omniclock/releases/)

旧 TokenClock Git 历史与标签保留。本次发布标签为 `omniclock-v1.0.0`，应用显示版本为 `1.0.0`。现有配置、数据目录和命令别名兼容。

## Verification and platform notes

Built and tested on the project's own Mac, Windows 11 and Debian hosts; no GitHub Actions tests. macOS packages contain Apple Silicon and Intel binaries (Glass: macOS 26+, Normal: macOS 12+). Linux x86_64 requires glibc 2.35+. Windows x86_64 requires Windows 11 and Microsoft Edge WebView2 Runtime.

Native material and browser behavior follow each platform. Quota results depend on valid local sign-in records and provider responses; missing cloud token evidence is not estimated. Public macOS packages retain the established ad-hoc signing format; they do not promise authorization continuity across updates.
