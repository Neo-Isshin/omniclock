# Windows parity and native material — 2026-11-08

This change completes the pending Windows port in an isolated checkout based on `35abc1f4`. The original Windows workspace and its uncommitted files are preserved. No GitHub Actions runs were used.

## Implemented

- Native Windows Desktop Acrylic, rounded system frames, light/dark and high-contrast fallback for the dropdown, summary and toolbox windows. Resizable standard window edges, DPI handling and saved sizes. Existing circular dial themes remain available.
- Summary with hourly 6/24-hour switch, same-time yesterday comparison, cache use, notebook, quota rings and separate reset labels, quota timeline, model/harness usage and estimates. Incomplete hourly receipts are labeled, never distributed into invented hours.
- Native tray single-click summary and double-click clock reveal/hide; temporary reveal leaves Always on top unchanged. Four selected quota providers in two rotating groups, ring click/secondary click actions, account selection, three Antigravity rings and larger labels.
- AI digest, notification preferences and unread state, notebook reminders, reorderable/hideable quick actions, model detection launcher, photo-based share image and native PNG export.
- Local tools with persisted results, incremental/full scans and masked key checks; network tools with all DNS rows scrollable, locations, plain leak summaries, DoH, IPv6, route comparison and on-demand Globalping reference.
- Current shared provider parsers, Claude Desktop receipt reading, pricing/release sources and OmniClock CLI naming with TokenClock compatibility.
- Windows-native Grok Bot credential decoding with DPAPI and authenticated AES-GCM, selected-account binding, no background authorization prompts. Unified X and legacy independent Cursor quota logic remain distinct.

## Compatibility corrections found on the real host

- WinHTTP preserves explicit bearer headers, returns content types needed for DoH, uses system proxy settings and avoids FoundationNetworking.dll.
- Swift timezone is initialized from the Windows timezone without changing the OS clock. Natural-day history and reminders use the same local zone.
- Python discovery handles Windows' case-insensitive `Path` environment key; its worker explicitly uses UTF-8 on Chinese Windows.
- WebView messages from remote network/model pages cannot invoke notebook, filesystem or credential commands. Native lifecycle messages are separate from page messages.
- Review-only CDP is loopback-bound and compiled out of production packages. Review and release build directories are separate.

## Verification

Windows 11 build 26300, Swift 6.3.3, Python 3.10; interactive desktop over the user's own SSH test machine. All acceptance data was isolated from installed settings/history.

- 296 XCTest cases: 278 passed, 18 explicit skips, zero failures. Separate Swift Testing image renderer passed. After the final missing-directory scan fix, all four LocalToolboxCache tests passed, including the new regression case.
- Real UI checks passed for DNS scroll and locations (16/16), DoH, 6/24-hour summary, four-provider group limits, account editor, notebook persistence/reminders, quick-action order/hiding, incremental/full scan and saved results, native PNG save, model workbench startup, resize, opacity/Acrylic restore, and tray single/double clicks.
- Native runtime and full UI acceptance results are recorded in the local deployment receipt and screenshots, outside the repository.
- Real Grok Bot credentials were successfully decoded silently on this host without Cursor installed. Its quota endpoint returned HTTP 401 despite an unexpired credential. This is not a successful quota reading and must not be presented as an authorization prompt loop.
- Claude App is not installed on this host; its fresh/stale/multiple-organization receipts are covered by fixture tests, not a live signed-in account check. No model generation calls were made.

No release version bump or remote push is part of this change.
