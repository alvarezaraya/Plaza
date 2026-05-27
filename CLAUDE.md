# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project overview

**Plaza** — Chilean cultural events app.

| Part | Stack | Notes |
|------|-------|-------|
| iOS app (`Plaza/`) | SwiftUI, iOS 26+ | Liquid Glass UI, no SPM packages |
| Scraper (`scraper_eventos.py`) | Python, Playwright | Outputs `eventos.json`, run by CI |

The app fetches `https://alvarezaraya.github.io/plaza/eventos.json` (GitHub Pages / Fastly CDN).  
`docs/eventos.json` mirrors the root copy; enable once via repo Settings → Pages → Source: `docs/` on `main`.

## Commands

```bash
# Run scraper locally (~300 events, 2-5 min)
pip install requests beautifulsoup4 playwright && python -m playwright install chromium
python3 scraper_eventos.py

# Build iOS app
open Plaza.xcodeproj   # requires Xcode + iOS 26 SDK
```

> Liquid Glass (`.glassEffect()`) only renders on the iOS 26 simulator or device, not in SwiftUI Previews.

## Architecture

### Data flow
```
GitHub Actions (06:00 + 17:00 UTC)
  → scraper_eventos.py → eventos.json committed to main
  → app URLSession (ETag cache) → EventoService
  → [Evento] DTO → [Event] model
  → parallel: VenueGeocoder (GPS fallback) + EventClassifier (Apple Intelligence)
```

### Key files

| File | Role |
|------|------|
| `EventoService.swift` | `@Observable` service: fetch, ETag cache, edits, geocoding, AI |
| `Models/Event.swift` | Core model, `Evento→Event` conversion, `parseName()`, `classify()`, filters |
| `Models/VenueGeocoder.swift` | Venue name → GPS via `MKGeocodingRequest`; UserDefaults cache |
| `Models/EventClassifier.swift` | Apple Intelligence (`FoundationModels`): category + artist bio |
| `Models/ComunaManager.swift` | Location filter state; `"Chile"` = show all |
| `Models/LocationManager.swift` | CoreLocation permissions, user coordinate, distance text |
| `Models/ReminderManager.swift` | Local notifications for saved events |
| `Theme/PlazaTheme.swift` | Design tokens: colors, fonts, spacing, `PlTag`; two themes |
| `App/RootTabView.swift` | iPhone tab bar + iPad sidebar (390pt panel + MapView) |
| `Screens/HomeView.swift` | Feed, card carousel (ImageCache prefetch), filter, header |
| `Screens/EventDetailView.swift` | Event detail: image, dates, map (tap → Apple Maps), AI bio |
| `Screens/AgendaView.swift` | Saved events grouped by date |
| `Screens/MapView.swift` | Interactive map with venue markers |
| `Screens/EventEditView.swift` | Manual field editor for saved events |
| `Screens/OnboardingView.swift` | Two-step welcome + permissions gate |
| `PlazaApp.swift` | Entry point: services, fonts, onboarding gate, theme hot-swap |

### UserDefaults keys

| Key | Content |
|-----|---------|
| `plaza_edited_events` | `[String: EditedFields]` — user edits |
| `plaza_saved_events` | `[String]` — saved stableIDs |
| `plaza_etag` | ETag for conditional JSON fetch |
| `plaza_cached_json` | Last fetched JSON (offline fallback) |
| `plaza_geocode_cache` | `[String: CachedCoordinate]` |
| `plaza_theme` | `"plaza"` or `"multicolor"` |
| `plaza_onboarding_done` | Bool |

### Event identity

`stableID` = source URL — persists edits/saves across refreshes.  
Events with the same lowercased title are grouped; extra dates land in `otherDates: [DateEntry]`.

### Coordinates

`eventos.json` includes `lat`/`lon` per event. Scraper resolution order:  
1. `COORDENADAS_FIJAS` (hardcoded dict of known venues — no bare generic names like "teatro municipal")  
2. Nominatim (OpenStreetMap, 1 req/s)  
3. City centroid fallback  

App: `Event.from()` uses JSON coords directly; `VenueGeocoder` only runs for events still at `defaultCoordinate`.

### Scraper enrichment

`enriquecer_evento()` runs in `ThreadPoolExecutor(max_workers=6)`.  
Wikipedia + DuckDuckGo calls are serialised via `threading.Semaphore(1)` (`_enrich_lock`) — one worker fetches at a time to avoid throttling.

### Scraper sources

| Source | Method |
|--------|--------|
| Ticketplus.cl | `requests` + BS4 (16 regions, cap 40/region) |
| Ticketpro.cl | `requests` + BS4 |
| PuntoTicket.com | `requests` + BS4 |
| Ticketmaster.cl | `requests` + BS4 (home only — anti-bot) |
| Passline.com | Playwright (home only — city URLs 403) |
| ComediaTicket.cl | Playwright (React SPA) |
| EsquinaRetornable.cl | `requests` + BS4 (WordPress) |
| CulturaAntofagasta.cl | RSS `/feed/` |
| CulturaIquique.cl | RSS `/feed/` |
| Ticketchile.cl | `requests` + BS4 |
| MasQueTickets.cl | `requests` + BS4 |
| Eventbrite.cl | Playwright (React SPA) |
| Joinnus.com/CL | Playwright |
| RSS Municipales | RSS `/feed/` (CulturaGob, CCPLM, GAM, CulturaValparaíso) |

### CI

`.github/workflows/scraper.yml` — 06:00 + 17:00 UTC.  
Chromium cached via `actions/cache@v4` (key: OS + requirements hash). Commits both `eventos.json` and `docs/eventos.json` to `main`.

## Design tokens

All tokens are `static var` (computed, theme-reactive) — never cache them in `let`.

| Token | Purpose |
|-------|---------|
| `Color.plBg / plSurface` | Background layers |
| `Color.plFg / plMuted / plDim / plHair` | Text + divider hierarchy |
| `Color.plAccent` | Primary CTA, icons, links |
| `Color.plCardLeft/Center/Right` | Card carousel colors |
| `Font.plDisplay()` | Large titles (Bricolage Grotesque) |
| `Font.plSans()` | UI text |
| `Font.plMono()` | Tags, labels |
| `Font.plSerifItalic()` | Bios, subtitles |
| `PlSpace.gutter / cardRadius / sectionSpacing` | Layout constants |

**Two themes** (`AppTheme.plaza` / `AppTheme.multicolor`):
- `plaza` — warm ambers and terracotta
- `multicolor` — esmeralda (`#0D7A54`) + oro antiguo (`#B8861A`) + azul cobalto (`#0040B0`); accent esmeralda vibrante

Theme changes hot-swap the `WindowGroup` via `.id(themeRaw)`.  
`isIPadSidebar` environment key → switch backgrounds from opaque to `.clear` inside the iPad panel.

## Card carousel (HomeView)

- Pool: up to 15 events with images from `filteredEvents`
- 3 visible at a time (front + 2 back slots); slot-based color assignment guarantees all 3 theme colors always visible
- `ImageCache` (`NSCache`, limit 60): `EventImageStack.onAppear` eagerly prefetches all pool URLs; `PlaybillCard` reads cache first → no swipe lag
- Cards are 2:3 aspect ratio (200×300); images top-cropped (`alignment: .top`)
