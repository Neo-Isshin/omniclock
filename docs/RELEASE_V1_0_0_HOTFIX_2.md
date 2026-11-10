## 热更新 2 / Hotfix 2 · 2026-11-10

应用版本保持 **v1.0.0**。本次更新 macOS Glass、macOS Normal 和 Linux 安装包，保留已发布的 Claude 额度热更新。

- 表盘只显示一个额度环时，直径由 42 缩至 38；双环和总结面板尺寸保持原样。
- 默认快捷工具将「网络工具箱」排在第一位；保留用户自定义的顺序和隐藏设置。
- DNS 自动核对解析器与出口的地理位置。结果都在同一城市时显示「地区一致」；尚未完成的查询单独提示。
- Gemini 改为检测官方网站的可达性。网站未提供客户端 IP 回显时明确说明，不再将它计入出口 IP 对照失败。
- macOS 的 Ailyre 新闻入口改用更大、更清晰的文字，适配浅色与深色背景。

macOS「关于」显示 **v1.0.0 · 热更新 2 / Hotfix 2**。按当前版本运行 `omniclock update --glass`、`omniclock update --normal`，Linux 使用 `omniclock update`；原 `tokenclock` 命令仍兼容。同版本热更新可能不会触发旧版版本号提醒，也可重新下载对应安装包。

**验证：**本轮 macOS 针对性测试、实际网络检测及 Linux 原生 GTK 测试已通过。实际网络检测中，21 个 DNS 来源均识别为洛杉矶，5 个可对照的 AI 出口一致；Gemini 可连接，但不提供出口 IP 回显。macOS 安装包包含 Apple Silicon 与 Intel。

**Windows：**对应源码已同步，但测试机暂未联机，本次保留原 Windows 安装包；没有使用 GitHub Actions 测试。

This v1.0.0 hotfix updates both macOS editions and Linux: smaller single quota rings, Network Toolbox first in the default toolbar, clearer DNS location assessment, accurate Gemini reachability reporting, and more legible macOS news buttons. Custom settings are preserved. Windows source is synchronized; its existing binary remains unchanged pending testing on the project's own Windows host.

下载 / Downloads: [Ailyre](https://www.ailyre.com/omniclock/releases/)

