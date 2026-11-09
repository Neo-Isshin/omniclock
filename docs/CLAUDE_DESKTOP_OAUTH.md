# Claude Desktop OAuth quota reader

Scope: macOS Glass and Normal, based on OmniClock v1.0.0. The installed runtime is unchanged until a signed-in Claude App can provide a real quota response.

## Confirmed source

The official Claude Desktop 4.23118.0 package stores its own OAuth cache in `config.json`, under `oauth:tokenCacheV2` and the older `oauth:tokenCache`. The embedded Code engine uses App-provided authorization. Static inspection of the checksum-verified official package confirmed:

- Electron safeStorage encryption; selected account in `lastKnownAccountUuid`.
- Account-prefixed keys contain client, organization, production API host and space-separated scopes. Legacy keys can omit the account prefix.
- Values contain `token` and a millisecond `expiresAt`; refresh tokens are deliberately ignored.
- The App itself queries `/api/oauth/profile` with a `user:profile` grant.

Official package: https://downloads.claude.ai/releases/darwin/universal/4.23118.0/Claude-8175c354eda704cea00fdeddfa69cea329dd321a.zip

SHA-256: `5b8feee3da048e26bbb29a5d601e97034f674ac3b76f7d0237751c46d6034b23`

## Resulting behavior

Fresh saved quota receipts remain first. When available, App OAuth is tried before the App's Cookie-based web request. It reuses the existing silent Safe Storage reader; only the existing explicit authorization button may permit a system prompt. No separate CLI is required, no Code session is started, and no credentials are copied into settings, refreshed or modified.

The parser filters the selected account, organization, production host, scope and actual expiry. It keeps current-cache tombstones authoritative and tries at most two grants. A successful API profile must confirm the account and organization before usage is shown. Config changes during a request invalidate its result. A local selection hint may restrict fallback, but never proves server identity. Other accounts and old snapshots cannot be substituted. A 429 stops further authenticated attempts. Model-specific limits remain separate from shared windows.

A valid result is labeled “Claude App · Shared subscription quota”. CLI credential files remain a fallback; an expired file no longer masks a subsequent fresh credential. Statistics, log readers, t/s cadence, proxy selection, Grok and signing/deployment are unchanged.

## Validation

Glass: 82 Claude-related tests, 81 passed, one existing live-account test skipped. Normal: 89 tests, 88 passed, one live-account test skipped. Thirteen new tests per edition cover encryption, App-only configuration, account and organization binding, v1/v2 precedence, revoked/expired entries, actual expiry, request bounds, config changes, rate limiting and read-only behavior. End-to-end transport tests use synthetic credentials and the real response schema; they make no external model requests.

The home Mac has no installed Claude Desktop and no Code credential file. Its remaining App caches are old encrypted empty objects. No real quota response was verified, and the installed runtime was not replaced.
