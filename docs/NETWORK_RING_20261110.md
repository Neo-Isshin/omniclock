# Network toolbox and single-ring update — 2026-11-10

- A single dial quota component is 38 points instead of 42 at the base scale. Its center stays fixed; two-component size and summary-panel sizing are unchanged.
- Network Toolbox leads the default shortcut order. The prior untouched six-button default migrates once; custom orders, hidden tools and empty toolbars are preserved.
- DNS automatically compares observed resolver locations with the web exit. Matching city/region/country is reported as location consistency. A manual source-IP allowlist remains an optional stronger comparison. Partial coverage stays partial, and geographic disagreement does not alone prove a leak.
- Gemini now receives a cookie-free HEAD request to its own homepage. Reachability and IP-echo capability are separate. It does not contribute a perpetual failure to the denominator of comparable exit-IP checks, and no Google server address or another domain's exit is substituted.
- Only static network-page assets were deployed. DNS/STUN server code and timers were not changed.

## Verification

macOS Glass: 37 targeted tests, one opt-in preview skipped, zero failures. macOS Normal: 24 tests, one preview skipped, zero failures. Final summary tests: five passed on each edition. JavaScript geography, partial coverage, strict allowlist, bilingual presentation and full DNS-result scrolling regressions passed.

A real native WebKit run passed: 21 DNS sources located in Los Angeles, `sameDNSCity`; five comparable AI exits matched. Gemini returned HTTP 200, `reachable`, without an exit-IP echo. The real network report remains local and private.

Linux: 217 tests in the owned Debian/GTK environment, 13 skips, zero failures. Windows source is synchronized, but its own SSH test machine was offline; no GitHub Actions were used.

The local Glass runtime was updated from the exact installed v1.0.0 source with only this change set. Unrelated modules, the unpublished-to-local Claude hotfix, installed Normal resources and user preferences were preserved. No new binary release was published.
