# Podium — Plan 3: Open-Source Launch

**Goal:** Ship Podium publicly: MIT license, real app icon, README with screenshots, CI, a v0.1.0 downloadable release, repository visibility set to public.

**Tasks:**
1. LICENSE (MIT, Levan Parastashvili) + this plan committed.
2. App icon: generated 1024px master → `App/Assets.xcassets/AppIcon.appiconset` (mac sizes) → `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in project.yml.
3. `podium-smoke seed <appId> <country> <terms> [days]` dev command: real app lookup + real current rank; optional deterministic demo history (days>0) for screenshots only.
4. Screenshots: seed demo data → launch → capture Keywords (hero) + reuse wizard shot → `docs/screenshots/`. Then wipe DB and re-seed real-only data (days=0) so the local install stays truthful.
5. README.md: what/why, features, install (unsigned zip → right-click Open), build from source, 5-minute Apple Ads guide, privacy, FAQ, roadmap, badges.
6. CI: `.github/workflows/ci.yml` — swift test + xcodebuild on macos-15.
7. Release v0.1.0: local Release build, zip via ditto, GitHub release with asset.
8. Repository: public visibility, description, topics.

**Verification:** package tests green, Release build succeeds, release asset downloadable, repo page renders README with images.
