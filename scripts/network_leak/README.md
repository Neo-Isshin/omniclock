# OmniClock network check

The macOS launcher creates an ephemeral WebKit window only after a click.
The embedded page runs one check; subsequent checks require another click.
An external-browser page opens idle and tests that browser's own environment.
Closing the native window tears down WebKit, fetches, and ICE connections.

## Service

- Public HTTPS page/API: `https://www.ailyre.com/tokenclock/network-check/`.
- Anonymous API listener: `127.0.0.1:8798`, behind the supplied nginx location.
- Authoritative DNS: `38.64.59.9:53`, UDP and TCP, only for `probe.tokenclock.ailyre.com`.
- STUN Binding: `38.64.59.9:3478/UDP`. No TURN, forwarding, media, or recursive DNS.
- DNS records: DNS-only A `ns.tokenclock.ailyre.com → 38.64.59.9`; NS delegation
  `probe.tokenclock.ailyre.com → ns.tokenclock.ailyre.com`.
- Installation: `/opt/tokenclock-network-check`, managed by
  `tokenclock-network-check.service`. The two narrowly scoped firewall accepts
  are also present in `/etc/nftables.conf`.

Each explicit check creates a random 128-bit observation token and three unique
probe names. The authority records incoming resolver IPs in memory and returns
NXDOMAIN with zero negative-cache TTL, so probes do not open HTTPS connections.
API rows expire at 120 seconds and are purged every 15 seconds. Application
request/IP/token logs are disabled; there is no measurement database.
Cloudflare's own proxy source ranges are taken from its published `ips-v4` and
`ips-v6` lists. Only trusted proxy peers can supply `CF-Connecting-IP`; nginx
overwrites both source headers before forwarding to the loopback API.

## Result interpretation

- DNS resolver sources can be upstream resolvers, rather than the resolver IP
  configured locally. Without optional expected resolver IPs, show observations
  for review. Do not infer a leak from location or an HTTP/DNS IP difference.
- The DNS card shows at most six sources with location data from IPWhois or
  Country.is. Lookups validate the returned IP; unavailable locations stay unknown.
  All observed sources still participate in the expected-DNS comparison. Successful
  lookups are cached in memory for six hours; there are no background lookups.
- Public ICE candidates differing from the HTTPS source within the same address
  family are risk evidence, not proof of VPN failure. An unmatched address family
  is compared with the corresponding HTTPS IPv4/IPv6 observations. A different
  known HTTPS exit needs review; no public candidate is inconclusive. Raw LAN
  addresses, including ICE related addresses, are reported as local-address
  exposure. mDNS and relay addresses do not count as a public-IP match.
- Every card has a plain-language conclusion and space for six detail rows.
  Native cards have the same height, including the mainland-reachability card;
  longer diagnostic details scroll within that area.
- The overall leak conclusion only includes DNS, WebRTC, IPv6 and DoH evidence.
  A successful web request or a reachable AI site cannot make an unknown leak
  check pass. Missing comparison data is separate from a failed measurement.
- No device/media permissions, persistent browser storage, or automatic refresh.
  The client stops after at most 25 seconds, after completion, or on cancellation.

## Verification

```sh
python3 scripts/network_leak/test_server.py
node scripts/network_leak/test_probe.cjs
node scripts/network_leak/test_presentation.cjs
swift test --filter NetworkLeakEndpointTests
TOKENCLOCK_NETWORK_LIVE_TEST=1 swift test --filter NetworkLeakLiveTests
```

The opt-in live test uses real WebKit, DNS, and STUN; it also closes the window
during a second run. Use the project's documented local Xcode/SDK configuration
when building on the development Mac. `nginx -t` must pass before a reload.
An optional `TOKENCLOCK_NETWORK_LIVE_REPORT` absolute path records local diagnostic
evidence with mode 0600; do not commit or publish that report's IP addresses.
Only add/modify this module's DNS names, location, service, and firewall rules;
do not reload the complete nftables ruleset or alter other site services.

## Extended Glass checks

On the same explicit Start action, the native WebKit bridge runs a fixed allowlist
of HTTPS requests through macOS URLSession's system proxy/PAC and VPN settings.
Its ephemeral session has no shared cookies, credentials or cache, refuses
redirects, and caps response bodies at 16 KiB. Cancellation/window teardown
invalidates the per-check session and rejects late callbacks by run ID. WebKit
messages are accepted only from the main frame of the check page's HTTPS origin.

- Exit consistency compares Ailyre, Cloudflare and ipify's observed client IPs.
- Country consistency compares data for the same explicit IP from IPWhois,
  Country.is and available Cloudflare traces. Multiple Cloudflare trace sites
  count as one geographic source; `colo` is not used as client geolocation.
- IPv6 uses IPv6-only ipify plus public IPv6 ICE candidates. No response means
  only "not observed". The optional IPv4-only policy flags unexpected IPv6;
  otherwise IPv6 availability alone is not classified as a leak.
- AI targets: chatgpt.com, claude.ai, gemini.google.com, api.openai.com,
  api.anthropic.com and api.x.ai. Client IP evidence comes from public trace
  responses when available. Gemini's unauthenticated HEAD request verifies only
  HTTP reachability. 200/401/403 or a blocked trace never proves routing or
  account/model availability. No model/completion endpoints are called.
- DoH checks issue real encrypted DNS queries to Cloudflare and Google, and use
  Cloudflare's client-IP echo for exit comparison. Matching observed exits and
  verified queries pass the tested scope; successful queries without exit proof
  are only partially confirmed. This does not establish which DoH provider another
  browser or application actually uses.

The WebRTC interpretation follows [RFC 8828](https://www.rfc-editor.org/rfc/rfc8828)
and the [WebRTC ICE candidate definitions](https://www.w3.org/TR/webrtc/).

The external-browser page uses CORS-readable IP/location probes and explicitly
asks users to use TokenClock for AI routing when cross-origin policies prevent
reliable checks. The browser result is not replaced with VPS-side probes.

Additional unit checks: `NetworkDiagnosticsTests` and
`node scripts/network_leak/test_probe.cjs`. The opt-in native live test covers
all six AI rows, IP/country rows, IPv6 state and cancellation during a second run.
