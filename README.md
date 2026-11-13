<div align="center">

[简体中文](README.zh-CN.md) · **English**

# 🕰️ OmniClock

**AI usage, subscription quotas, news, reminders, and practical tools—on your desktop.**

[![Downloads](https://img.shields.io/badge/Downloads-GitHub-10B981?style=for-the-badge)](https://github.com/Neo-Isshin/omniclock/releases/latest)
[![macOS 12+](https://img.shields.io/badge/macOS-12%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](#platforms)
[![Liquid Glass](https://img.shields.io/badge/macOS%2026%2B-Liquid%20Glass-00B0F0?style=for-the-badge&logo=apple&logoColor=white)](#platforms)
[![Windows](https://img.shields.io/badge/Windows-11-0078D4?style=for-the-badge)](#windows)
<br>
[![Linux](https://img.shields.io/badge/Linux-GTK3%20AppImage-FCC624?style=for-the-badge&logo=linux&logoColor=black)](#platforms) [![LINUX DO](docs/badges/linux-do.svg)](https://linux.do/)

[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![MIT License](https://img.shields.io/badge/License-MIT-3B82F6.svg)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/Neo-Isshin/omniclock?style=social)](https://github.com/Neo-Isshin/omniclock)

</div>

<div align="center">
<table>
  <tr>
    <td align="center" valign="bottom"><img src="docs/screenshots/glass.png" alt="Liquid Glass clock" width="220"><br><sub><b>Liquid Glass</b><br>A glanceable desktop overview</sub></td>
    <td align="center" valign="bottom"><img src="docs/screenshots/dropdown.png" alt="Usage details" width="230"><br><sub><b>Usage details</b><br>Tools, sessions, and models</sub></td>
    <td align="center" valign="bottom"><img src="docs/screenshots/normal_en.png" alt="Normal clock edition" width="220"><br><sub><b>Normal</b><br>Theme-aware native presentation</sub></td>
  </tr>
</table>
</div>

---

**OmniClock**, formerly **TokenClock**, brings the everyday details of working with AI into one desktop companion. The clock shows activity and selected quotas; its panels provide usage history, costs, a notebook, AI news, and local or network diagnostics.

**OmniClock v1.0.2 marks the completion of major feature development.** This release includes the macOS Glass, macOS Normal and Linux packages. The latest verified Windows package is v1.0.0. The repository retains its history. Use `omniclock` on macOS/Linux; existing `tokenclock` commands, settings and usage history remain compatible.

## Features

| Area | What you can do |
|---|---|
| **Desktop overview** | See today's tokens, messages, active tools, weather, and subscription rings. Choose a theme, size, and optional always-on-top behavior. |
| **Usage and API-equivalent cost** | Explore harnesses, sessions, and models; switch the cache-read basis; inspect cost estimates and supported Fast/Priority breakdowns. Recent generation speed refreshes every three minutes. |
| **Subscription quotas** | Review supported provider accounts, remaining allowances and reset times. Select up to four providers, displayed two at a time. Configure renewal reminders 1, 2, 3, or 7 days before a known or manually entered renewal date. |
| **History and sharing** | Browse the last 30 days or a date range. A single-day range shows hourly usage. Export a share image for a day, recent days, a month, or a calendar week, with optional cache reads and selectable artwork. |
| **AI digest and notebook** | Read Ailyre's AI digest with provider logos and topic labels. Keep plain-text notes and timed reminders. Digest refreshes every two hours; application update checks run every twelve hours. |
| **Network Toolbox** | Run DNS/DoH, WebRTC, IPv6, exit-IP/location, AI-domain routing, and mainland-reachability reference checks on demand. Results distinguish possible issues from inconclusive checks. |
| **Local Toolbox and Model Detect** | Inspect environment conflicts and disk use, scan logs locally for exposed secrets, check clock offset, and validate configured API keys with masked results. Model Detect reviews available session evidence and supports explicitly initiated external checks. |

The macOS and Windows summary panels bring together hourly usage, comparison with yesterday, cache use, quota reset times, the notebook, and tool/model lists. Shortcut visibility and order are editable. Linux provides corresponding functions through its native menus and panels; some checks open the browser.

## Platforms

| Platform | Edition | Current distribution |
|---|---|---|
| macOS 26+ | Glass or Normal | v1.0.2 universal packages for Apple Silicon and Intel |
| macOS 12–25 | Normal | v1.0.2 universal package; opaque themed dial |
| Linux x86_64 | Normal, GTK3/Cairo | v1.0.2 AppImage; glibc 2.35+; extraction fallback when FUSE is unavailable |
| Windows 11 x86_64 | Normal, Win32 | v1.0.0 portable package; native Acrylic panels with system fallback |

Glass has its own transparent materials and optical effects. Normal keeps its own themes and contrast rules. In Normal, the quick **Text Color** control affects the detail panel; dial text has a separate appearance setting.

The editions share accounting, pricing and usage history formats. Windows uses Win32/WebView2 with native Acrylic; Linux keeps GTK panels and opens browser-only DNS/WebRTC checks on the Ailyre page. Project tests run locally or on project-owned machines, not GitHub Actions.

## Installation

### macOS and Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.sh | bash
```

The installer selects the supported edition, verifies package checksums, and installs both commands:

```bash
omniclock doctor
omniclock start --normal
omniclock restart
omniclock update
omniclock update --check
```

`update --check` downloads the current installer without installing or restarting anything. Use `--glass` or `--normal` when you want a specific macOS edition. `omniclock uninstall` removes the installed runtime; the CLI commands are retained for reinstalling.

#### Existing TokenClock installations

Your old command remains valid:

```bash
tokenclock update
# After the CLI update, either name works:
omniclock doctor
tokenclock doctor
```

The new installer installs `omniclock` as the main implementation and `tokenclock` as a forwarding entry point. Both use the same installation and settings. Existing `TOKENCLOCK_*` environment overrides, `~/.tokenclock`, application identifiers, and executable names remain compatible. There is no second copy of your usage history to maintain.

The previous `https://www.ailyre.com/tokenclock/install.sh` address remains available. If you install the CLI manually from this repository, install both files together into the same directory on your `PATH`.

macOS may request permission to access protected or external-disk folders. Current ad-hoc-signed packages do not guarantee that permissions carry across binary updates.

### Windows

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.ps1)))
```

This installs the verified Windows v1.0.0 package for the current user, with SHA-256 verification. The installation path and executable retain the TokenClock name for compatibility. The `omniclock`/`tokenclock` shell commands described above apply to macOS and Linux.

<details>
<summary>Windows installer options</summary>

```powershell
# Install without launching; optionally create a Start Menu shortcut.
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.ps1))) -NoStart -StartMenuShortcut

# Inspect installation state.
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.ps1))) -Action Check

# Uninstall while retaining Windows user settings.
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Neo-Isshin/omniclock/main/cli/install.ps1))) -Action Uninstall
```

</details>

## Everyday use

- **Click the dial** to open usage details. Expand a tool, session, or model to inspect its contributions.
- **Use the first-row shortcuts** for tools and history. The shortcut editor controls visibility and order.
- **Switch to AI digest** to read news within the lower part of the dropdown; use Back to return to usage.
- **Open Subscription Quota** to select providers and accounts for the dial. Click a ring to advance when multiple groups are available; right-click it to open the quota panel.
- **On macOS/Windows, click the menu-bar/tray icon** for today's summary. Double-click to bring the dial temporarily forward or hide it; the right-click menu also provides visibility controls.
- **Right-click the dial** for general and appearance settings, source paths, notifications, updates, and restart.

The detail panel supports horizontal resizing, and notifications support resizing in both directions. On some nonactivating macOS panels, the pointer may remain an arrow at a resizable edge; the bottom resize handle remains available.

## Supported data sources

Current sources across the four editions cover Codex, Claude Code, Cursor Agent, Grok Bot, Antigravity, OpenClaw, Gemini CLI, Hermes, OpenCode, Qwen Code, Copilot CLI, Grok CLI, Aider, Cline, Continue, ZCode, Kilo Code, Pi, OMP, PiG, DSH, Command Code, and Freebuff, subject to the records each tool actually saves.

- Custom paths and external disks can be selected in **Settings → Data Source Paths**.
- Freebuff exposes completed local reply counts, not token receipts; these counts are excluded from token and API-equivalent cost totals.
- Cloud-only chat activity is not converted into invented token estimates.
- Speed and TTFT appear only when the source contains suitable timing evidence. Missing values remain unavailable.
- Quota cards reuse available saved quota records or permitted sign-ins. Some accounts require a user-initiated connection or authorization. A shared subscription is deduplicated only when sharing is confirmed.

See [additional harnesses](docs/ADDITIONAL_HARNESSES.md), [hourly history](docs/HOURLY_HISTORY.md), and [subscription billing](docs/SUBSCRIPTION_BILLING.md) for details.

## Accounting and privacy

The main token figure excludes cache reads by default; you can include them explicitly. Cache writes, output, and reasoning follow the source's recorded accounting rules. API-equivalent cost uses the [Ailyre pricing catalog](https://www.ailyre.com/prices/tokenclock.json), with user overrides supported. It is an estimate at public API rates, **not a subscription bill**.

Usage collection reads local logs and databases without modifying the harness's records. Quota, weather, news, and user-triggered network checks contact their respective services. Local secret scans stay on the device. API-key checks send credentials only to the paired configured endpoint and mask them in results. External Model Detect checks require confirmation of their scope and cost; their results are evidence, not proof of model identity.

A successful network probe is not a guarantee that every app or route is leak-free. Mainland reachability results are references; an ordinary timeout is not reported as proof of GFW blocking.

## Local API

When enabled, the read-only HTTP API binds to loopback:

```bash
curl http://127.0.0.1:9988/api/usage
curl 'http://127.0.0.1:9988/api/history?days=30'
```

The port is configurable. API-equivalent costs carry `costBasis: "api_equivalent_public_list"`.

## Screenshots

<div align="center">
<p><img src="docs/screenshots/usage_overview.png" alt="Usage history" width="780"></p>
<table>
  <tr>
    <td align="center"><img src="docs/screenshots/subscription_quota.png" alt="Subscription quota panel" width="460"></td>
    <td align="center"><img src="docs/screenshots/themes.png" alt="Theme selection" width="280"></td>
  </tr>
</table>
</div>

## Development and help

```bash
git clone https://github.com/Neo-Isshin/omniclock.git
cd omniclock
```

`main` contains macOS Glass, `normal` contains macOS Normal, `windows-port` contains Windows, and `codex/linux-theme-parity` contains Linux. Internal Swift targets and bundle names retain `TokenClock` for compatibility. See [platform behavior](PLATFORM_PARITY.md) and [Model Detect integration](docs/MODEL_DETECT_INTEGRATION.md) before changing shared components.

Run `omniclock doctor` first if an installation is not behaving as expected. For missing usage, check that the selected source path contains real usage records. For quota failures, distinguish a missing local record, permission request, expired sign-in, and provider-side rejection.

[Report an issue](https://github.com/Neo-Isshin/omniclock/issues) · [Gitea mirror](https://gitea.nxc8335.cloud/nxc8335/omniclock) · [Ailyre](https://www.ailyre.com/)

Friend link · [LINUX DO](https://linux.do/)

## License and acknowledgements

[MIT](LICENSE). Bundled third-party libraries and artwork retain their own licenses and attribution. Ailyre supplies the digest, pricing catalog, and network-check page; network tools also use services including Cloudflare, Google, and Globalping where indicated in the interface. OmniClock is an independent project and is not an official client of the supported AI providers.
