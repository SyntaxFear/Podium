# Podium Upgrade — Advanced (API v1 correctness → features → Liquid Glass)

Inputs: full API map (99 endpoints, 63 read — agent report 2026-08-17), verified 24-finding code review, user requests (bulk add ✅ shipped, multi-country Discover, show all API fields, competitor analysis, Liquid Glass everywhere, short of nothing the read API offers).

## Phase A — API correctness (the plumbing Apple actually shipped)

Contract corrections vs what we built from early docs:
- Base URL is `https://api.ads.apple.com/v1/` (we used api.searchads.apple.com — v5 host).
- Scope header is `X-AP-Context: adAccountId={id}` (not orgId). Discover accounts via `GET /me` → `GET /acls` (returns ad accounts + roles); org details via `GET /orgs/{id}`.
- Search-term popularity: POST `/insights/apps/search-term-popularity/query` body = `{ timeRange { start, end (YYYY-MM-DD), granularity: WEEKLY_SUN_SAT | MONTHLY }, filters [ {field, operator, value[]} ], sorting (≤2), pagination {offset, pageSize ≤5000} }`. Rows: `week|month, countryOrRegion, genre (free-text like "TRAVEL"), searchTerm (≥500 searches, top 500/country/genre), rankInGenre, searchPopularityInGenre, searchPopularity1to100, searchPopularity1to5`. Envelope `result.rows + pagination{totalCount}`.
- Suggestions (keywords/phrases/categories/target-cpas): body = RecommendationQueryRequest; **filters on promotedObjectId + promotedObjectType are required**; pageSize ≤1000; responses `{text|phrase|category, popularity}` / TargetCpaSuggestion.
- Rate limits: honor `Retry-After` on 429.

Tasks:
- [ ] A1 AdsAPIClient: new base URL, `adAccountId` context (AdsCredentials gains `adAccountId`, old `orgId` kept for decode), `me()`, `acls()`, `org()` GETs; 429 Retry-After.
- [ ] A2 Insights models rewritten to the real contract (+fixtures/tests).
- [ ] A3 Suggestions models rewritten (filters-based, promotedObjectId required) (+fixtures/tests); PopularityService takes the app's adamId.
- [ ] A4 Wizard: after token validation call /me + /acls, auto-pick single ad account (picker if several), store adAccountId; org-scoped validation call.
- [ ] A5 podium-smoke updated (popularity command uses new contract; new `accounts` command printing /acls).

## Phase B — Advanced features (read-only)

- [ ] B1 Discover v2: multi-country (parallel per-country queries merged, country column), week/month toggle, free-text + common-list genre, ALL returned fields as columns (rankInGenre, pop 1-100, in-genre, 1-5, week), pagination ("Load more"), Track ✓ feedback.
- [ ] B2 Reports dashboards (campaigns → ad groups → keywords → search terms) with spend/taps/installs/CPI + Apple's suggestedBid per keyword; Charts; date range; groupBy country/device. Fixture-driven until live creds verified.
- [ ] B3 Impression share screen (share-of-voice per term + market-size estimate).
- [ ] B4 Keyword expansion tab: keyword+phrase+category suggestions merged, dedupe vs tracked, one-click track.
- [ ] B5 Competitor compare: track competitor apps (public data), side-by-side rank table on shared keywords, rating trends.
- [ ] B6 Recommendations monitor (target-CPA + daily-budget reads with Apple's 7-day projections).
- [ ] B7 Change-history timeline (event annotations on charts).
- [ ] B8 Remaining review meds/lows: per-view error surfacing, notifications toggle reflects permission, CSV consolidation into CSVExporter, storefront-aware app search/lookup, openWindow for menu bar, popularity default sort desc, delta vs previous day, localization catalog + accessibility labels.

## Phase C — Native Liquid Glass design pass

- [ ] C1 Audit every component; adopt macOS 26 Liquid Glass: glass button styles/effects on toolbars, sheets, wizard cards, menu bar content; native materials everywhere; raise deployment target to macOS 26 (decision: yes — design-first app, user on 26).
- [ ] C2 Polish: empty states, hover states, animations (default motion), consistent typography; screenshot refresh for README; release v0.2.0 (zip replace).

Execution: inline, task-by-task, tests+build green per task, push per phase. Live verification of B2/B3/B6/B7 requires the pending Apple Ads API user (task #23).
