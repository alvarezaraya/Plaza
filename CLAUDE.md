# CLAUDE.md

**Plaza** — App de eventos culturales chilenos.
iOS app (SwiftUI, iOS 26+, Liquid Glass, sin SPM) + scraper Python que genera `eventos.json` vía CI.
JSON en `https://alvarezaraya.github.io/Plaza/eventos.json` (GitHub Pages, ruta sensible a mayúsculas: repo `Plaza`). Requiere repo **público** + Pages habilitado (`docs/` on `main`).

## Comandos

```bash
# Scraper local (~300 eventos, 2-5 min)
pip install requests beautifulsoup4 playwright && python -m playwright install chromium
python3 scraper_eventos.py

# App
open Plaza.xcodeproj  # Xcode + iOS 26 SDK
```
> `.glassEffect()` solo renderiza en simulador/dispositivo iOS 26, no en Previews.

## Flujo de datos

```
CI (06:00 + 17:00 UTC) → scraper → eventos.json → GitHub Pages
  → URLSession (ETag) → EventoService → [Evento] DTO → [Event]
  → paralelo: VenueGeocoder (fallback GPS) + EventClassifier (Apple Intelligence)
```

## Archivos clave

| Archivo | Rol |
|---------|-----|
| `EventoService.swift` | `@Observable`: fetch ETag, edits, geocoding, AI |
| `Models/Event.swift` | Modelo central, conversión Evento→Event, parseName, classify, filtros |
| `Models/EventClassifier.swift` | FoundationModels: categoría + bio artista |
| `Models/VenueGeocoder.swift` | Fallback venue→GPS, caché UserDefaults |
| `Models/ComunaManager.swift` | Filtro ubicación; `"Chile"` = sin filtro; fallback escalonado comuna→región→Chile (`byComuneTiered`) |
| `Models/LocationManager.swift` | CoreLocation, distanceText() |
| `Models/ReminderManager.swift` | UNUserNotificationCenter, 1h antes del evento |
| `Theme/PlazaTheme.swift` | Tokens (colores, fuentes, spacing), PlTag, dos temas |
| `App/RootTabView.swift` | Tab bar iPhone + sidebar iPad 390pt |
| `Screens/HomeView.swift` | Feed, carrusel (ImageCache), CalendarBadge, filtro |
| `Screens/EventDetailView.swift` | Detalle: imagen, bio IA, mapa (tap → Apple Maps) |
| `Screens/AgendaView.swift` | Eventos guardados por fecha |
| `Screens/MapView.swift` | Mapa interactivo con marcadores por venue |
| `Screens/EventEditView.swift` | Editor manual de campos |
| `Screens/OnboardingView.swift` | Bienvenida + permisos |
| `PlazaApp.swift` | Entry point, fuentes, onboarding, hot-swap de tema |

## UserDefaults

| Clave | Contenido |
|-------|-----------|
| `plaza_edited_events` | `[String: EditedFields]` |
| `plaza_saved_events` | `[String]` stableIDs guardados |
| `plaza_etag` | ETag para cache condicional (JSON en `Caches/plaza_cached_events.json`) |
| `plaza_geocode_cache` | `[String: CachedCoordinate]` |
| `plaza_ai_categories` | `[String: String]` categoría IA por stableID |
| `plaza_theme` | `"plaza"` / `"multicolor"` |
| `plaza_onboarding_done` | Bool |

## Modelo de eventos

`stableID` = URL fuente — persiste edits/saves entre refreshes.
Eventos con el mismo título **y subtítulo** (lowercased) se agrupan — giras del mismo show en varias ciudades se colapsan, pero shows distintos del mismo artista no; fechas extra van a `otherDates: [DateEntry]`.

## Scraper

**Coordenadas**: JSON incluye `lat`/`lon`. Orden de resolución: `COORDENADAS_FIJAS` (no añadir nombres genéricos como "teatro municipal") → Nominatim (1 req/s, `addressdetails=1`) → centroide de ciudad. La respuesta de Nominatim **rellena `ciudad`** cuando viene vacía o como sentinel `"Chile"` (backfill en `geocodificar_todos`, sin requests extra).

**Enriquecimiento**: `ThreadPoolExecutor(max_workers=6)`. Wikipedia/DuckDuckGo serializados con `Semaphore(1)` para no saturar APIs.

**Fuentes** (15): Ticketplus · Ticketpro · PuntoTicket · Ticketmaster · Passline · ComediaTicket · EsquinaRetornable · CulturaAntofagasta · CulturaIquique · Ticketchile · MasQueTickets · Eventbrite · Joinnus · **GAM** (`scrape_gam`: sitio SSR sin RSS, lee JSON-LD `schema.org/Event` de cada show crawleando las categorías de `/que-hacer-en-gam/`) · RSS Municipales (CulturaGob, CCLM, CulturaValparaíso).

**Feeds RSS municipales** (`_scrape_rss_municipal`, compartido por CulturaGob/CCLM/CulturaValparaíso/CulturaAntofagasta/CulturaIquique): son blogs de noticias, no de eventos. `_rss_es_evento` filtra notas de prensa y recopilaciones (`RSS_RUIDO` vs `RSS_EVENTO`); la ubicación se infiere con `detectar_ciudad`/`detectar_venue` sobre el título (feed = fallback); `limpiar_nombre_rss` limpia el titular sin borrar meses ni ciudades. Las fechas sin año se anclan al `<pubDate>` del post (no se bumpean a futuro). **CCLM**: el dominio cambió de `ccplm.cl` a `cclm.cl`.

**Salud**: `verificar_salud` compara el run con el JSON previo y devuelve `(criticos, advertencias)`. **Críticos** (abortan con `exit 1`): una fuente grande (≥`UMBRAL_FUENTE_CRITICA`=15) cae a 0, o el total baja >50%. **Advertencias** (solo informan): una fuente pequeña/RSS cae a 0. Override: `PLAZA_SKIP_HEALTHCHECK=1`. El JSON incluye `por_fuente: {fuente: count}`. `generado_en` en UTC.

**Tests**: `test_scraper.py` (unittest, sin red) cubre las funciones puras de parsing y el guardia de salud. Correr: `python3 test_scraper.py`.

**CI**: `.github/workflows/scraper.yml` — 06:00 + 17:00 UTC. Corre tests → scraper → commit. Chromium cacheado con `actions/cache@v4`. Commit de `eventos.json` y `docs/eventos.json`.

## Design tokens

Todos `static var` (reactivos al tema) — nunca cachear en `let`.

`plBg/plSurface` · `plFg/plMuted/plDim/plHair` · `plAccent` · `plCardLeft/Center/Right`
`plDisplay()` (Bricolage Grotesque) · `plSans()` · `plMono()` · `plSerifItalic()`
`PlSpace.gutter/cardRadius/sectionSpacing`

**Temas**: `plaza` (ambers/terracota) · `multicolor` (esmeralda `#0D7A54` + oro `#B8861A` + cobalto `#0040B0`).
Hot-swap vía `WindowGroup.id(themeRaw)`. `isIPadSidebar` env key → fondos `.clear` en el panel iPad.

## Carrusel (HomeView)

- Pool: hasta 15 eventos con imagen de `filteredEvents`
- 3 visibles (frente + 2 atrás); colores por slot — garantiza los 3 colores del tema siempre visibles
- `ImageCache` (NSCache, límite 60): prefetch al aparecer → sin lag al deslizar
- Tarjetas 2:3 (200×300); imagen recortada desde arriba (`alignment: .top`)

## EventRowContent

Cada fila muestra un `CalendarBadge` unificado (fecha + ícono de categoría en un mismo contenedor):
- Columna izquierda (36pt): franja de mes (plAccent) + número de día (plDisplay)
- Divisor vertical 0.5pt plHair
- Columna derecha: ícono de categoría centrado (plAccent)
