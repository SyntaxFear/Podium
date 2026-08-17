# Podium — Design Document

**Date:** 2026-08-17
**Status:** Approved by Levani (2026-08-17)
**Version:** V1 scope

## What is Podium

Podium is a free, open-source, fully native macOS app that gives indie iOS developers
a complete App Store Optimization (ASO) and Apple Ads analytics cockpit — built on
Apple's official **Apple Ads Platform API v1** (released 2026-08-14). It is the first
open-source tool built on this API.

**One-line pitch:** track your app's keyword rankings, see Apple's official search
popularity data, and monitor your Apple Ads performance — free forever, your data
never leaves your Mac.

## Goals

1. **Super simple:** an indie dev goes from download to seeing live data in under
   5 minutes, guided by an in-app setup wizard.
2. **Super advanced:** expose *everything* readable from the Apple Ads Platform API —
   insights, suggestions, and reports — plus organic keyword rank tracking.
3. **Super native:** pure Swift/SwiftUI with macOS-quality polish (menu bar presence,
   native charts, notifications, Keychain, sandboxed). No web views, no Electron.
4. **Free forever, trustworthy:** open source (MIT), zero servers. Each user brings
   their own free Apple Ads account. Credentials stay in the local Keychain.

## Non-goals (V1)

- **No campaign management (writes).** V1 is strictly read-only against Apple Ads.
  Creating/editing campaigns, budgets, or bids is V2 (prepare-and-confirm model).
- No Google Play / Android support.
- No hosted service, accounts, or telemetry.
- No Windows/Linux.

## Target user

Indie iOS developers (or tiny teams) who ship apps on the App Store, on Macs,
who currently either pay $50–500/month for SaaS ASO tools or fly blind.
Secondary: developers already running small Apple Ads campaigns who want free
reporting outside Apple's clunky web UI.

## Product design

### Screens

1. **Setup wizard (first run)**
   - Explains what's needed: a free Apple Ads account.
   - Generates the EC private/public key pair locally (one click).
   - Shows step-by-step, screenshot-guided instructions: where to paste the public
     key in the Apple Ads UI (Account Settings → API), and where to copy
     `clientId` / `teamId` / `keyId` back into Podium.
   - Validates credentials by requesting a token, then imports the org's apps.
   - Also works in "organic-only mode": skip Apple Ads setup entirely and just
     track keyword ranks + app metadata via public endpoints (zero credentials).

2. **My apps**
   - Add apps by App Store search or bundle ID (public iTunes Lookup API).
   - Per-app overview cards: icon, current rating, rating count, tracked-keyword
     movement summary (▲ improved / ▼ dropped counts since yesterday).

3. **Keywords** (per app)
   - Table: keyword · Apple popularity score (official, 0–100) · my rank ·
     rank trend sparkline (30 days) · country.
   - Add/remove tracked keywords; multi-country tracking per keyword.
   - Rank history detail view with native Swift Charts.
   - Data sources: rank via public App Store search endpoint; popularity via
     official suggestions endpoints where the term appears.

4. **Discover**
   - **Top search terms:** official ranked list per storefront country + genre,
     weekly or monthly (`POST /v1/insights/apps/search-term-popularity/query`).
   - **Suggestions:** seed by my app / brand / terms → related keywords, phrases,
     and categories with popularity scores (`POST /v1/suggestions/{keywords,phrases,categories}/query`).
   - One-click "track this keyword" from any row.
   - Clearly label the API's known limitation: popularity scores are aggregated
     across storefronts (no per-country score), and arbitrary-term lookup is not
     supported by Apple — Podium shows what Apple provides, honestly.

5. **Ads performance** (visible only when the account has campaigns)
   - Read-only reports: impressions, taps, installs, spend, CPA/CPT, per campaign /
     ad group / keyword, with date-range picker and Swift Charts.
   - Target-CPA suggestions surface (`POST /v1/suggestions/target-cpa/query`).

6. **Settings**
   - Credentials management (re-key, remove), refresh schedule, storefront
     defaults, notification preferences, data export (CSV), app version/updates.

### Native experience details

- Menu bar item with today's headline (e.g., "kids drawing ▲2 → #8").
- Native notifications on meaningful rank changes (threshold configurable).
- Automatic daily refresh (while app or menu bar agent runs); manual refresh anywhere.
- Keyboard-first navigation, standard macOS toolbar/sidebar idioms, dark mode.
- Sandboxed; hardened runtime; notarized.

## Architecture

Two-layer split, one repository:

```
Podium/                     — repo root (MIT license)
├── Podium/                 — macOS app target (SwiftUI, macOS 15+)
├── PodiumKit/              — SwiftPM package: all logic, no UI
│   ├── Auth/               — EC key generation, JWT (ES256) client secret,
│   │                          OAuth2 token exchange, Keychain storage
│   ├── AdsAPI/             — typed client for Apple Ads Platform API v1
│   │                          (insights, suggestions, reports; paging, rate limits)
│   ├── PublicStore/        — iTunes Search/Lookup client: rank checks, app
│   │                          metadata, ratings (no auth needed)
│   ├── Storage/            — local SQLite (GRDB): apps, keywords, rank snapshots,
│   │                          popularity snapshots, report caches
│   └── Refresh/            — scheduler + snapshot diffing (drives notifications)
└── docs/
```

- **PodiumKit is UI-free and reusable** — a future CLI or MCP server target links
  the same package (V2).
- All Apple Ads calls authenticate via OAuth2: locally-generated EC private key →
  ES256-signed JWT client secret (≤180-day expiry) → 1-hour access tokens,
  auto-refreshed. Private key and secrets live only in the macOS Keychain.

## Data flow

1. Refresh tick (daily or manual) →
2. PublicStore: for each tracked keyword × country, fetch App Store search results,
   record my app's position →
3. AdsAPI (if connected): pull latest popularity/top-terms snapshots and report
   deltas →
4. Storage: append snapshots (never overwrite history) →
5. Diff vs. previous snapshot → post notifications for threshold-crossing changes →
6. UI reads from Storage only (offline-friendly: last data always visible).

## Error handling

- **Token expiry / 401:** auto-regenerate client secret and token; if the key was
  revoked, surface a fix-it banner that reopens the wizard at the right step.
- **Rate limits / 429:** exponential backoff; spread keyword checks over time;
  cap per-refresh request volume.
- **Public endpoint shape changes:** rank checks are best-effort; failures mark the
  snapshot "unavailable" rather than recording false ranks.
- **Offline:** everything renders from local storage with a "last updated" stamp.
- **No Ads account:** app fully functions in organic-only mode; Ads-only screens
  show a friendly connect prompt.

## Testing

- Unit tests in PodiumKit: JWT/client-secret creation (against Apple's documented
  format), API response decoding from recorded fixtures, rank-parsing, snapshot
  diffing, storage migrations.
- Integration smoke test behind a flag using a real sandbox/org account (manual).
- UI: lightweight ViewInspector/snapshot checks for the main tables; manual QA
  checklist for the wizard.

## Distribution & community

- GitHub public repo, MIT license, README with screenshots + 5-minute setup GIF.
- Releases: notarized DMG via GitHub Actions; Homebrew cask once stable.
- Positioning: "first open-source tool on Apple's official Ads Platform API."
  (OpenASO exists but uses unofficial endpoints; Podium is official-API-first,
  adds ads reporting, and the guided wizard.)

## Success criteria (V1)

- Fresh Mac → data on screen in ≤5 minutes following the wizard.
- Tracks ≥50 keywords × 5 countries without hitting rate limits.
- Zero third-party servers involved; works fully offline after first sync.
- A non-technical indie dev can use every screen without reading docs.

## Roadmap after V1

- **V2:** campaign management with prepare-and-confirm writes; MCP server target
  so AI agents (Claude Code etc.) can query your Podium data; CLI.
- **V3:** Google Play support; competitor tracking; review monitoring/alerts.
