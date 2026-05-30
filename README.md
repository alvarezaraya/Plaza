# Plaza 🎭

**Descubre eventos culturales en Chile** — conciertos, teatro, comedia, exposiciones y más, en una sola app.

Plaza reúne eventos de **14 fuentes de venta de entradas y centros culturales chilenos** y los presenta en una interfaz nativa de iOS con un diseño editorial cuidado. Un scraper en Python recolecta, geocodifica y enriquece los eventos cada día; la app SwiftUI los consume desde un JSON servido por GitHub Pages.

---

## ✨ Qué hace

- 📅 **Feed de eventos** actualizado dos veces al día mediante CI automático
- 🗺️ **Mapa interactivo** con marcadores agrupados por recinto
- 🔖 **Agenda personal** — guarda eventos y recibe un recordatorio 1 hora antes
- 🎨 **Clasificación con IA** (Apple Intelligence / FoundationModels) — categoría del evento + biografía del artista
- 📍 **Filtro por ubicación** — comuna, región o todo Chile, con fallback escalonado
- 🌈 **Dos temas visuales** (`plaza` y `multicolor`) con cambio en caliente
- ✏️ **Edición manual** de cualquier campo, persistida entre actualizaciones
- 🖼️ **Carrusel destacado** con caché de imágenes y prefetch

---

## 🏗️ Arquitectura

```
CI (06:00 + 17:00 UTC) → scraper_eventos.py → eventos.json → GitHub Pages
   → URLSession (ETag) → EventoService → [Evento] DTO → [Event]
        ├── VenueGeocoder   (recinto → coordenadas, con fallback GPS)
        └── EventClassifier (Apple Intelligence: categoría + bio)
```

El scraper produce `eventos.json`, que se publica en GitHub Pages
(`https://alvarezaraya.github.io/plaza/eventos.json`). La app lo descarga con
caché condicional por **ETag**, lo convierte en modelos `Event` y, en paralelo,
geocodifica los recintos y clasifica cada evento con IA en el dispositivo.

---

## 📂 Componentes

### Scraper (Python)

| Archivo | Rol |
|---------|-----|
| [`scraper_eventos.py`](scraper_eventos.py) | Scrapea las 14 fuentes, geocodifica, enriquece, agrupa y valida la salud del run |
| [`test_scraper.py`](test_scraper.py) | Tests `unittest` sin red: funciones puras de parsing + guardia de salud |
| [`eventos.json`](eventos.json) | Salida del scraper, servida vía GitHub Pages |
| [`.github/workflows/scraper.yml`](.github/workflows/scraper.yml) | CI: corre tests → scraper → commit del JSON |

### App (SwiftUI, iOS 26+)

| Archivo | Rol |
|---------|-----|
| `Plaza/PlazaApp.swift` | Entry point: fuentes, onboarding, hot-swap de tema |
| `Plaza/App/RootTabView.swift` | Tab bar en iPhone, sidebar en iPad |
| `Plaza/EventoService.swift` | `@Observable`: fetch con ETag, ediciones, geocoding, IA |
| `Models/Event.swift` | Modelo central; conversión `Evento → Event`, parseo, clasificación y filtros |
| `Models/EventClassifier.swift` | FoundationModels: categoría del evento + bio del artista |
| `Models/VenueGeocoder.swift` | Recinto → coordenadas, caché en UserDefaults |
| `Models/LocationManager.swift` | CoreLocation, `distanceText()` |
| `Models/ComunaManager.swift` | Filtro por ubicación; fallback comuna → región → Chile |
| `Models/ReminderManager.swift` | Notificaciones locales 1 h antes del evento |
| `Screens/HomeView.swift` | Feed, carrusel, badge de calendario, filtros |
| `Screens/EventDetailView.swift` | Detalle: imagen, bio IA, mapa (tap → Apple Maps) |
| `Screens/AgendaView.swift` | Eventos guardados, agrupados por fecha |
| `Screens/MapView.swift` | Mapa interactivo con marcadores por recinto |
| `Screens/EventEditView.swift` | Editor manual de campos |
| `Screens/OnboardingView.swift` | Bienvenida + solicitud de permisos |
| `Theme/PlazaTheme.swift` | Tokens de diseño (colores, fuentes, spacing), `PlTag`, dos temas |

---

## 🔎 Cómo funciona el scraper

**Fuentes (14):** Ticketplus · Ticketpro · PuntoTicket · Ticketmaster · Passline ·
ComediaTicket · EsquinaRetornable · CulturaAntofagasta · CulturaIquique ·
Ticketchile · MasQueTickets · Eventbrite · Joinnus · RSS Municipales
(CulturaGob, CCPLM, GAM, CulturaValparaíso).

- **Coordenadas** (`lat`/`lon`): se resuelven en orden `COORDENADAS_FIJAS` →
  Nominatim (1 req/s) → centroide de la ciudad. La respuesta de Nominatim además
  rellena la `ciudad` cuando viene vacía.
- **Enriquecimiento:** `ThreadPoolExecutor(max_workers=6)`; las consultas a
  Wikipedia/DuckDuckGo se serializan con `Semaphore(1)` para no saturar las APIs.
- **Feeds RSS municipales:** son blogs de noticias, así que `_rss_es_evento`
  filtra notas de prensa y recopilaciones, y la ubicación se infiere del título.
- **Agrupación:** eventos con el mismo título **y** subtítulo se colapsan (una gira
  en varias ciudades se vuelve un solo evento con `otherDates`).
- **Salud:** `verificar_salud` compara el run con el JSON previo. Si una fuente
  grande cae a 0 o el total baja >50 %, **aborta** con `exit 1`. Override con
  `PLAZA_SKIP_HEALTHCHECK=1`.

---

## 🚀 Inicio rápido

### App iOS

```bash
open Plaza.xcodeproj   # Requiere Xcode con SDK de iOS 26
```

> `.glassEffect()` (Liquid Glass) solo renderiza en simulador/dispositivo iOS 26,
> no en las Previews de Xcode.

### Scraper

```bash
pip install requests beautifulsoup4 playwright && python -m playwright install chromium
python3 scraper_eventos.py        # ~300 eventos, 2–5 min
python3 test_scraper.py           # tests (sin red)
```

---

## 📲 Requisitos

- **iOS 26+** — usa Liquid Glass y Apple Intelligence
- **Xcode** con el SDK de iOS 26 (proyecto sin Swift Package Manager)
- **Scraper:** Python 3 + `requests`, `beautifulsoup4`, `playwright`

---

## 🔄 Flujo de CI

`.github/workflows/scraper.yml` se ejecuta a las **06:00 y 17:00 UTC**:

1. Corre los tests (`test_scraper.py`).
2. Ejecuta el scraper (Chromium cacheado con `actions/cache@v4`).
3. Hace commit de `eventos.json` y `docs/eventos.json`.

GitHub Pages publica `docs/eventos.json`. Para activarlo una sola vez:
**Settings → Pages → carpeta `docs/` en `main`**.

---

## 📄 Licencia

Pendiente.
