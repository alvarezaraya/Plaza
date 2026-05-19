"""
scraper_eventos.py  v12
======================
Extrae eventos culturales con imagen y descripción desde:
  - Ticketplus.cl    (Región de Antofagasta)
  - Ticketpro.cl     (filtrando ciudades del norte)
  - PuntoTicket.com  (página /todos, filtrando por ciudad en slug/texto)
  - Ticketmaster.cl  (filtrando ciudades del norte via JSON-LD)
  - Passline.com     (playwright — ciudad en URL o búsqueda)
  - ComediaTicket.cl (playwright — todos los shows de humor)

Requisitos:
    pip install requests beautifulsoup4
    pip install playwright && python3 -m playwright install chromium

Uso:
    python3 scraper_eventos.py
"""

import json
import re
import time
from datetime import datetime

import requests
from bs4 import BeautifulSoup

# ── Configuración ────────────────────────────────────────────────────────────

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    )
}

CIUDADES_OBJETIVO = [
    "antofagasta", "calama", "iquique", "arica",
    "tocopilla", "mejillones", "taltal",
]

VENUES_CONOCIDOS = [
    "teatro municipal de antofagasta",
    "teatro municipal de calama",
    "teatro municipal de iquique",
    "teatro municipal",
    "rock and soccer",
    "centro cultural estación",
    "sala andamios",
    "enjoy antofagasta",
    "estadio regional",
    "club hípico",
    "gimnasio olímpico",
]

OUTPUT_FILE = "eventos.json"
PAUSA = 0.8

NOMBRES_TICKETERA = {"ticketplus", "ticketpro", "puntoticket", "ticketmaster", "passline", "comediaticket"}

MESES_ES = {
    "ene": 1, "enero": 1,
    "feb": 2, "febrero": 2,
    "mar": 3, "marzo": 3,
    "abr": 4, "abril": 4,
    "may": 5, "mayo": 5,
    "jun": 6, "junio": 6,
    "jul": 7, "julio": 7,
    "ago": 8, "agosto": 8,
    "sep": 9, "septiembre": 9,
    "oct": 10, "octubre": 10,
    "nov": 11, "noviembre": 11,
    "dic": 12, "diciembre": 12,
}

MESES_TEXTO = {
    1: "enero", 2: "febrero", 3: "marzo", 4: "abril",
    5: "mayo", 6: "junio", 7: "julio", 8: "agosto",
    9: "septiembre", 10: "octubre", 11: "noviembre", 12: "diciembre",
}

MESES_PATTERN = "|".join(MESES_ES.keys())

# Sufijos y prefijos de ticketera a eliminar de nombres
SUFIJOS_TICKETERA = r"\s*[-–]\s*(Ticketplus|Ticketpro|PuntoTicket|Ticketmaster|Passline|ComediaTicket)\s*$"
PREFIJOS_TICKETERA = r"^(Ticketplus|Ticketpro|PuntoTicket|Ticketmaster|Passline|ComediaTicket)\s*[-–|:]\s*"


# ── Utilidades ───────────────────────────────────────────────────────────────

def get(url):
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.raise_for_status()
        return r
    except requests.RequestException as e:
        print(f"  ⚠️  {url} → {e}")
        return None


def limpiar(texto):
    return re.sub(r"\s+", " ", texto).strip()


def es_ciudad_objetivo(texto):
    return any(c in texto.lower() for c in CIUDADES_OBJETIVO)


def parsear_fecha(dia, mes_str):
    mes_str = mes_str.lower().strip()
    mes_num = MESES_ES.get(mes_str)
    if not mes_num:
        return "", ""
    anio = datetime.now().year
    ahora = datetime.now()
    if mes_num < ahora.month or (mes_num == ahora.month and int(dia) < ahora.day):
        anio += 1
    try:
        fecha = datetime(anio, mes_num, int(dia))
        iso = fecha.strftime("%Y-%m-%d")
        texto = f"{int(dia)} de {MESES_TEXTO[mes_num]} de {anio}"
        return iso, texto
    except ValueError:
        return "", ""


def extraer_fecha_de_texto(texto):
    patron = re.search(
        rf"(\d{{1,2}})\s+(?:de\s+)?({MESES_PATTERN})",
        texto, re.IGNORECASE
    )
    if patron:
        return parsear_fecha(patron.group(1), patron.group(2))
    return "", ""


def detectar_venue(texto):
    texto_lower = texto.lower()
    for v in VENUES_CONOCIDOS:
        if v in texto_lower:
            return v.title()
    return ""


def detectar_ciudad(texto):
    texto_lower = texto.lower()
    for c in CIUDADES_OBJETIVO:
        if c in texto_lower:
            return c.capitalize()
    return ""


def nombre_desde_slug(url):
    """Genera un nombre legible desde el slug de la URL como último recurso."""
    slug = url.rstrip("/").split("/")[-1]
    # Quitar sufijos de ID aleatorio tipo "_x18hd"
    slug = re.sub(r"_[a-z0-9]{4,8}$", "", slug)
    return limpiar(slug.replace("-", " ")).title()


def limpiar_nombre(nombre_crudo, venue="", ciudad=""):
    nombre = nombre_crudo
    nombre = re.sub(PREFIJOS_TICKETERA, "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"^Entradas para\s+", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(SUFIJOS_TICKETERA, "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"Desde:?\s*CLP\s*[\d\.]+\s*CLP?", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"Desde:?\s*\$?\s*[\d\.]+", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"CLP\s*[\d\.]+", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"\$\s*[\d\.]+", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(
        rf"\d{{1,2}}\s+(?:de\s+)?(?:{MESES_PATTERN})(?:\s+(?:de\s+)?\d{{4}})?",
        "", nombre, flags=re.IGNORECASE
    )
    if venue:
        nombre = re.sub(re.escape(venue), "", nombre, flags=re.IGNORECASE)
    for c in CIUDADES_OBJETIVO:
        nombre = re.sub(rf"\b{c}\b", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"\s*-\s*$", "", nombre)
    nombre = re.sub(r"^\s*-\s*", "", nombre)
    nombre = re.sub(r"\s*-\s*-\s*", " - ", nombre)
    return limpiar(nombre).strip(" -–—·")


def limpiar_nombre_para_busqueda(nombre):
    """Extrae solo el nombre del artista/evento para Wikipedia y DuckDuckGo."""
    nombre = re.sub(PREFIJOS_TICKETERA, "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"^Entradas\s+(?:para\s+)?", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(SUFIJOS_TICKETERA, "", nombre, flags=re.IGNORECASE)
    # Quitar sufijos de tour/gira (con o sin guion)
    nombre = re.sub(r"\s*[-–]\s*(Tour|Gira|En Vivo|Live|Chile)\s*\d{0,4}\s*$", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"\s+Gira\s+\d+\s+a[ñn]os?\b.*$", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"\s+(Tour|Gira|En Vivo|Live)\s.*$", "", nombre, flags=re.IGNORECASE)
    # Quitar ciudades y años del término de búsqueda
    for c in CIUDADES_OBJETIVO:
        nombre = re.sub(rf"\b{c}\b", "", nombre, flags=re.IGNORECASE)
    nombre = re.sub(r"\b\d{4}\b", "", nombre)
    # Quedarse solo con el primer segmento (artista principal)
    partes = re.split(r"\s+[-–]\s+", nombre)
    nombre = partes[0].strip() if partes else nombre
    # Quitar "EN [VENUE EN MAYÚSCULAS]" al final (og:title a veces trunca la info del venue)
    nombre = re.sub(r"\s+EN\s+[A-Z].+$", "", nombre)
    # Quitar preposiciones sueltas al final
    nombre = re.sub(r"\s+\b(en|de|a|para|con)\b\s*$", "", nombre, flags=re.IGNORECASE)
    return limpiar(nombre).strip(" -–—·")


def extraer_detalle(url):
    r = get(url)
    if not r:
        return "", "", "", "", "", ""

    soup = BeautifulSoup(r.text, "html.parser")

    og_title = ""
    tag = soup.find("meta", property="og:title")
    if tag and tag.get("content"):
        og_title = limpiar(tag["content"])

    imagen = ""
    tag = soup.find("meta", property="og:image")
    if tag and tag.get("content"):
        imagen = tag["content"].strip()
    if not imagen:
        tag = soup.find("meta", attrs={"name": "twitter:image"})
        if tag and tag.get("content"):
            imagen = tag["content"].strip()

    descripcion = ""
    tag = soup.find("meta", property="og:description")
    if tag and tag.get("content"):
        descripcion = limpiar(tag["content"])
    if not descripcion:
        tag = soup.find("meta", attrs={"name": "description"})
        if tag and tag.get("content"):
            descripcion = limpiar(tag["content"])

    fecha_iso, fecha_texto = extraer_fecha_de_texto(descripcion)
    if not fecha_iso:
        fecha_iso, fecha_texto = extraer_fecha_de_texto(og_title)

    venue = detectar_venue(og_title) or detectar_venue(descripcion)

    return og_title, imagen, descripcion, fecha_iso, fecha_texto, venue


def extraer_ciudad_jsonld(soup):
    """Extrae la ciudad desde JSON-LD (schema.org Event), útil para Ticketmaster."""
    for tag in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(tag.string or "")
            if not isinstance(data, dict):
                continue
            # Puede ser un solo objeto o una lista
            objetos = data if isinstance(data, list) else [data]
            for obj in objetos:
                if obj.get("@type") == "Event":
                    location = obj.get("location", {})
                    address = location.get("address", {})
                    localidad = (
                        address.get("addressLocality", "")
                        or address.get("addressRegion", "")
                        or location.get("name", "")
                    )
                    if localidad:
                        return localidad
        except Exception:
            continue
    return ""


# ── Scraper 1: Ticketplus ────────────────────────────────────────────────────

def scrape_ticketplus():
    print("\n🔍 Ticketplus.cl ...")
    r = get("https://ticketplus.cl/states/region-de-antofagasta")
    if not r:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    base = []
    vistos = set()  # evitar duplicados de URL

    for a in soup.find_all("a", href=re.compile(r"/events/")):
        href = a.get("href", "")
        evento_url = f"https://ticketplus.cl{href}" if href.startswith("/") else href
        if evento_url in vistos:
            continue
        vistos.add(evento_url)

        texto = limpiar(a.get_text(" "))
        if not texto or len(texto) < 5:
            continue

        precio_match = re.search(r"CLP\s*([\d\.]+)", texto)
        precio = precio_match.group(1) if precio_match else ""

        base.append({"texto_crudo": texto, "precio": precio, "url": evento_url})

    print(f"  → Obteniendo detalle de {len(base)} eventos...")
    eventos = []
    for i, b in enumerate(base):
        print(f"    [{i+1}/{len(base)}] {b['url'].split('/')[-1][:50]}...")
        og_title, imagen, desc, fecha_iso, fecha_texto, venue = extraer_detalle(b["url"])

        nombre_base = og_title or desc or b["texto_crudo"]
        if not venue:
            venue = detectar_venue(b["texto_crudo"])
        ciudad = detectar_ciudad(b["texto_crudo"]) or "Antofagasta"

        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(b["texto_crudo"])

        nombre = limpiar_nombre(nombre_base, venue=venue, ciudad=ciudad)

        eventos.append({
            "fuente": "Ticketplus",
            "nombre": nombre,
            "venue": venue,
            "descripcion": desc,
            "fecha_iso": fecha_iso,
            "fecha_texto": fecha_texto,
            "precio_desde_clp": b["precio"],
            "ciudad": ciudad,
            "imagen_url": imagen,
            "url": b["url"],
        })
        time.sleep(PAUSA)

    print(f"  ✅ {len(eventos)} eventos")
    return eventos


# ── Scraper 2: Ticketpro ─────────────────────────────────────────────────────

def scrape_ticketpro():
    print("\n🔍 Ticketpro.cl ...")
    r = get("https://www.ticketpro.cl/")
    if not r:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    base = []
    vistos = set()  # evitar duplicados de URL

    for a in soup.find_all("a", href=re.compile(r"/evento/")):
        texto = limpiar(a.get_text(" "))
        href = a.get("href", "")
        if not texto or len(texto) < 5 or not es_ciudad_objetivo(texto):
            continue

        evento_url = f"https://www.ticketpro.cl{href}" if href.startswith("/") else href
        if evento_url in vistos:
            continue
        vistos.add(evento_url)

        precio_match = re.search(r"\$\s*([\d\.]+)", texto)
        precio = precio_match.group(1) if precio_match else ""
        ciudad_det = detectar_ciudad(texto) or ""

        base.append({"texto_crudo": texto, "precio": precio, "ciudad": ciudad_det, "url": evento_url})

    print(f"  → Obteniendo detalle de {len(base)} eventos...")
    eventos = []
    for i, b in enumerate(base):
        print(f"    [{i+1}/{len(base)}] {b['url'].split('/')[-1][:50]}...")
        og_title, imagen, desc, fecha_iso, fecha_texto, venue = extraer_detalle(b["url"])

        # ticketpro.cl a veces pone og:title = "Ticketpro" o "Ticketpro - evento" — se limpia vía PREFIJOS_TICKETERA en limpiar_nombre
        nombre_base = og_title or desc or b["texto_crudo"]
        if not venue:
            venue = detectar_venue(b["texto_crudo"])
        ciudad = b["ciudad"] or detectar_ciudad(b["texto_crudo"])

        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(b["texto_crudo"])

        nombre = limpiar_nombre(nombre_base, venue=venue, ciudad=ciudad)
        if not nombre or nombre.lower().strip() in NOMBRES_TICKETERA:
            nombre = nombre_desde_slug(b["url"])

        eventos.append({
            "fuente": "Ticketpro",
            "nombre": nombre,
            "venue": venue,
            "descripcion": desc,
            "fecha_iso": fecha_iso,
            "fecha_texto": fecha_texto,
            "precio_desde_clp": b["precio"],
            "ciudad": ciudad,
            "imagen_url": imagen,
            "url": b["url"],
        })
        time.sleep(PAUSA)

    print(f"  ✅ {len(eventos)} eventos")
    return eventos


# ── Scraper 3: PuntoTicket ───────────────────────────────────────────────────

def scrape_puntoticket():
    """
    PuntoTicket cambió su estructura: ya no usa /ciudad/antofagasta.
    Ahora se usa /todos y se filtra por ciudad en el slug o el texto del evento.
    """
    print("\n🔍 PuntoTicket.com ...")
    r = get("https://www.puntoticket.com/todos")
    if not r:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    base = []
    vistos = set()

    for a in soup.find_all("a", href=True):
        href = a.get("href", "")
        texto = limpiar(a.get_text(" "))

        # Normalizar URL
        if href.startswith("/"):
            evento_url = f"https://www.puntoticket.com{href}"
        elif href.startswith("https://www.puntoticket.com"):
            evento_url = href
        else:
            continue

        # Excluir páginas de categoría, cuenta y rutas de nav
        excluir = ["musica", "deportes", "teatro", "familia", "especiales",
                   "todos", "Account", "Cliente", "paginas", "#", "evento/"]
        if any(x in href for x in excluir):
            continue

        if len(href) <= 3 or len(texto) < 4:
            continue

        # Filtrar por ciudad: slug o texto deben mencionar ciudad objetivo
        if not es_ciudad_objetivo(href) and not es_ciudad_objetivo(texto):
            continue

        if evento_url in vistos:
            continue
        vistos.add(evento_url)

        ciudad = detectar_ciudad(href) or detectar_ciudad(texto) or ""
        base.append({"texto_crudo": texto, "ciudad": ciudad, "url": evento_url})

    # También buscar en /evento/[slug] con ciudad en el slug
    for a in soup.find_all("a", href=re.compile(r"/evento/")):
        href = a.get("href", "")
        texto = limpiar(a.get_text(" "))
        evento_url = f"https://www.puntoticket.com{href}" if href.startswith("/") else href
        if evento_url in vistos:
            continue
        if not es_ciudad_objetivo(href) and not es_ciudad_objetivo(texto):
            continue
        vistos.add(evento_url)
        ciudad = detectar_ciudad(href) or detectar_ciudad(texto) or ""
        base.append({"texto_crudo": texto, "ciudad": ciudad, "url": evento_url})

    print(f"  → Obteniendo detalle de {len(base)} eventos...")
    eventos = []
    for i, b in enumerate(base):
        print(f"    [{i+1}/{len(base)}] {b['url'].split('/')[-1][:50]}...")
        og_title, imagen, desc, fecha_iso, fecha_texto, venue = extraer_detalle(b["url"])

        nombre_base = og_title or desc or b["texto_crudo"]
        if not venue:
            venue = detectar_venue(b["texto_crudo"])
        ciudad = b["ciudad"] or detectar_ciudad(f"{og_title} {desc}")

        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(b["texto_crudo"])

        nombre = limpiar_nombre(nombre_base, venue=venue, ciudad=ciudad)

        eventos.append({
            "fuente": "PuntoTicket",
            "nombre": nombre,
            "venue": venue,
            "descripcion": desc,
            "fecha_iso": fecha_iso,
            "fecha_texto": fecha_texto,
            "precio_desde_clp": "",
            "ciudad": ciudad,
            "imagen_url": imagen,
            "url": b["url"],
        })
        time.sleep(PAUSA)

    print(f"  ✅ {len(eventos)} eventos")
    return eventos


# ── Scraper 4: Ticketmaster ──────────────────────────────────────────────────

def scrape_ticketmaster():
    """
    Ticketmaster Chile se concentra en Santiago.
    Se valida la ciudad usando JSON-LD (schema.org) en la página del evento,
    que es más fiable que buscar texto libre en la descripción.
    """
    print("\n🔍 Ticketmaster.cl ...")
    base = []
    vistos = set()

    for ciudad in ["antofagasta", "calama", "iquique", "arica"]:
        url = f"https://www.ticketmaster.cl/buscar?q={ciudad}"
        r = get(url)
        if not r:
            continue
        soup = BeautifulSoup(r.text, "html.parser")

        for a in soup.find_all("a", href=re.compile(r"/event/")):
            href = a.get("href", "")
            if href.startswith("../event/"):
                evento_url = href.replace("../", "https://www.ticketmaster.cl/")
            elif href.startswith("/event/"):
                evento_url = f"https://www.ticketmaster.cl{href}"
            elif href.startswith("http"):
                evento_url = href
            else:
                continue

            if evento_url in vistos:
                continue
            vistos.add(evento_url)
            texto = limpiar(a.get_text(" "))
            base.append({"texto_crudo": texto, "ciudad_busqueda": ciudad.capitalize(), "url": evento_url})
        time.sleep(PAUSA)

    print(f"  → Obteniendo detalle de {len(base)} eventos...")
    eventos = []
    for i, b in enumerate(base):
        print(f"    [{i+1}/{len(base)}] {b['url'].split('/')[-1][:50]}...")
        r = get(b["url"])
        if not r:
            continue
        soup = BeautifulSoup(r.text, "html.parser")

        # Intentar JSON-LD primero para ciudad exacta
        ciudad_jsonld = extraer_ciudad_jsonld(soup)
        todo_texto = f"{ciudad_jsonld} {b['texto_crudo']}".lower()

        # También leer og: tags
        og_title, imagen, desc, fecha_iso, fecha_texto, venue = "", "", "", "", "", ""
        tag = soup.find("meta", property="og:title")
        if tag and tag.get("content"):
            og_title = limpiar(tag["content"])
        tag = soup.find("meta", property="og:image")
        if tag and tag.get("content"):
            imagen = tag["content"].strip()
        tag = soup.find("meta", property="og:description")
        if tag and tag.get("content"):
            desc = limpiar(tag["content"])
        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(desc)
        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(og_title)
        venue = detectar_venue(og_title) or detectar_venue(desc)

        todo_texto += f" {og_title} {desc} {venue}".lower()

        if not es_ciudad_objetivo(todo_texto):
            continue

        nombre_base = og_title or desc or b["texto_crudo"]
        if not venue:
            venue = detectar_venue(todo_texto)
        ciudad = detectar_ciudad(ciudad_jsonld) or detectar_ciudad(todo_texto) or b["ciudad_busqueda"]

        nombre = limpiar_nombre(nombre_base, venue=venue, ciudad=ciudad)

        eventos.append({
            "fuente": "Ticketmaster",
            "nombre": nombre,
            "venue": venue,
            "descripcion": desc,
            "fecha_iso": fecha_iso,
            "fecha_texto": fecha_texto,
            "precio_desde_clp": "",
            "ciudad": ciudad,
            "imagen_url": imagen,
            "url": b["url"],
        })
        time.sleep(PAUSA)

    print(f"  ✅ {len(eventos)} eventos")
    return eventos


# ── Scraper 5: Passline ──────────────────────────────────────────────────────

def scrape_passline():
    """
    Passline.com bloquea requests con 403. Usa playwright.
    Intenta primero URLs de ciudad, luego la página principal de Chile.
    """
    print("\n🔍 Passline.com (playwright) ...")
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("  ⚠️  playwright no instalado — omitiendo Passline.")
        print("       Ejecuta: pip install playwright && python3 -m playwright install chromium")
        return []

    # Posibles URL patterns de ciudad en Passline
    urls_ciudad = [
        ("Antofagasta", "https://www.passline.com/ciudad/antofagasta"),
        ("Iquique",     "https://www.passline.com/ciudad/iquique"),
        ("Calama",      "https://www.passline.com/ciudad/calama"),
        ("Chile",       "https://www.passline.com/"),  # fallback: página principal
    ]

    base = []
    vistos = set()

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(user_agent=HEADERS["User-Agent"])
        page = ctx.new_page()

        for ciudad, url in urls_ciudad:
            try:
                # domcontentloaded es más rápido y menos propenso a timeout que networkidle
                page.goto(url, wait_until="domcontentloaded", timeout=30000)
                page.wait_for_timeout(5000)
                page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
                page.wait_for_timeout(2000)

                links = page.eval_on_selector_all(
                    "a[href]",
                    "els => els.map(el => ({href: el.href, text: el.innerText.trim()}))"
                )

                for link in links:
                    href = link.get("href", "")
                    texto = limpiar(link.get("text", ""))
                    if (
                        href not in vistos
                        and len(texto) > 3
                        and "passline.com" in href
                        # Excluir páginas de sistema: raíz, login, cuenta, categoría
                        and not re.search(r"passline\.com/?$|/(login|cuenta|cuenta|category|terminos|politica|faq|contacto|home|nosotros)\b", href, re.IGNORECASE)
                        and (es_ciudad_objetivo(href) or es_ciudad_objetivo(texto) or ciudad != "Chile")
                    ):
                        vistos.add(href)
                        c = detectar_ciudad(href) or detectar_ciudad(texto) or ciudad
                        base.append({"texto_crudo": texto, "ciudad": c, "url": href})

            except Exception as e:
                print(f"  ⚠️  Passline {ciudad}: {e}")
            time.sleep(PAUSA)

        browser.close()

    print(f"  → Obteniendo detalle de {len(base)} eventos...")
    eventos = []
    for i, b in enumerate(base):
        print(f"    [{i+1}/{len(base)}] {b['url'].split('/')[-1][:50]}...")
        og_title, imagen, desc, fecha_iso, fecha_texto, venue = extraer_detalle(b["url"])

        nombre_base = og_title or desc or b["texto_crudo"]
        if not venue:
            venue = detectar_venue(b["texto_crudo"])
        ciudad = b["ciudad"]

        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(b["texto_crudo"])

        nombre = limpiar_nombre(nombre_base, venue=venue, ciudad=ciudad)

        eventos.append({
            "fuente": "Passline",
            "nombre": nombre,
            "venue": venue,
            "descripcion": desc,
            "fecha_iso": fecha_iso,
            "fecha_texto": fecha_texto,
            "precio_desde_clp": "",
            "ciudad": ciudad,
            "imagen_url": imagen,
            "url": b["url"],
        })
        time.sleep(PAUSA)

    print(f"  ✅ {len(eventos)} eventos")
    return eventos


# ── Scraper 6: ComediaTicket ─────────────────────────────────────────────────

def scrape_comediaticket():
    """
    ComediaTicket.cl es una SPA React. Usa playwright.
    Incluye todos los shows (sin filtro de ciudad) porque el humor es itinerante.
    """
    print("\n🔍 ComediaTicket.cl (playwright) ...")
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("  ⚠️  playwright no instalado — omitiendo ComediaTicket.")
        print("       Ejecuta: pip install playwright && python3 -m playwright install chromium")
        return []

    EXCLUIR = {"/shop/faq", "/shop/terms", "/shop/post_with_us", "/home", "/shop/home"}

    base = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(user_agent=HEADERS["User-Agent"])
        page = ctx.new_page()

        try:
            # El home solo muestra nav; los eventos están en /shop
            all_links = []
            for ruta in ["https://comediaticket.cl/shop", "https://comediaticket.cl/home"]:
                page.goto(ruta, wait_until="domcontentloaded", timeout=30000)
                page.wait_for_timeout(5000)  # tiempo para hidratación de React
                page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
                page.wait_for_timeout(2000)
                page.evaluate("window.scrollTo(0, 0)")
                page.wait_for_timeout(1000)
                batch = page.eval_on_selector_all(
                    "a",
                    """els => els.map(el => ({
                        href: el.href || el.getAttribute('href') || '',
                        text: el.innerText.trim()
                    }))"""
                )
                all_links.extend(batch)

            links = all_links
            print(f"    (playwright encontró {len(links)} links en total)")

            vistos = set()
            for link in links:
                href = link.get("href", "") or ""
                texto = limpiar(link.get("text", ""))

                if not href or href == "javascript:void(0)":
                    continue

                # Normalizar a URL absoluta
                if href.startswith("/"):
                    full_url = f"https://comediaticket.cl{href}"
                    path = href
                elif "comediaticket.cl" in href:
                    full_url = href
                    path = "/" + "/".join(href.split("/")[3:])
                else:
                    continue

                if full_url in vistos or len(texto) < 3:
                    continue
                if any(path == ex or path.startswith(ex + "/") for ex in EXCLUIR):
                    continue
                # Solo links internos que parezcan eventos (tienen path con contenido)
                if path in ("/", "") or re.match(r"^/\?", path):
                    continue

                vistos.add(full_url)
                base.append({"texto_crudo": texto, "url": full_url})

        except Exception as e:
            print(f"  ⚠️  ComediaTicket: {e}")
        finally:
            browser.close()

    print(f"  → Obteniendo detalle de {len(base)} eventos...")
    eventos = []
    for i, b in enumerate(base):
        print(f"    [{i+1}/{len(base)}] {b['url'].split('/')[-1][:50]}...")
        og_title, imagen, desc, fecha_iso, fecha_texto, venue = extraer_detalle(b["url"])

        # Si la página no tiene og:title usable, probablemente no es un evento
        if not og_title and not desc:
            continue

        nombre_base = og_title or desc or b["texto_crudo"]
        todo_texto = f"{og_title} {desc} {venue} {b['texto_crudo']}".lower()

        if not venue:
            venue = detectar_venue(todo_texto)
        ciudad = detectar_ciudad(todo_texto) or "Chile"

        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(b["texto_crudo"])

        nombre = limpiar_nombre(nombre_base, venue=venue, ciudad=ciudad)

        eventos.append({
            "fuente": "ComediaTicket",
            "nombre": nombre,
            "venue": venue,
            "descripcion": desc,
            "fecha_iso": fecha_iso,
            "fecha_texto": fecha_texto,
            "precio_desde_clp": "",
            "ciudad": ciudad,
            "imagen_url": imagen,
            "url": b["url"],
        })
        time.sleep(PAUSA)

    print(f"  ✅ {len(eventos)} eventos")
    return eventos


# ── Enriquecimiento: Wikipedia + DuckDuckGo ─────────────────────────────────

def _safe_json(r):
    """Parsea JSON de una respuesta; retorna {} si la respuesta está vacía o es inválida."""
    try:
        text = r.text.strip() if r else ""
        if not text:
            return {}
        return r.json()
    except Exception:
        return {}


def buscar_wikipedia(nombre):
    nombre_buscar = re.sub(r"\s*\(.*?\)", "", nombre).strip()
    if len(nombre_buscar) < 3:
        return ""

    for lang in ("es", "en"):
        try:
            search_url = (
                f"https://{lang}.wikipedia.org/w/api.php"
                f"?action=query&list=search&srsearch={requests.utils.quote(nombre_buscar)}"
                f"&srlimit=1&format=json"
            )
            r = requests.get(search_url, headers=HEADERS, timeout=10)
            data = _safe_json(r)
            results = data.get("query", {}).get("search", [])
            if not results:
                continue

            page_title = results[0]["title"]
            summary_url = (
                f"https://{lang}.wikipedia.org/api/rest_v1/page/summary/"
                f"{requests.utils.quote(page_title, safe='')}"
            )
            r2 = requests.get(summary_url, headers=HEADERS, timeout=10)
            summary = _safe_json(r2)
            extract = summary.get("extract", "")
            if len(extract) > 50:
                return extract
        except Exception as e:
            print(f"    ⚠️  Wikipedia ({lang}): {e}")
            continue

    return ""


def buscar_duckduckgo(nombre):
    try:
        query = re.sub(r"\s*\(.*?\)", "", nombre).strip()
        url = f"https://api.duckduckgo.com/?q={requests.utils.quote(query)}&format=json&no_html=1"
        r = requests.get(url, headers=HEADERS, timeout=10)
        data = _safe_json(r)
        abstract = data.get("AbstractText", "")
        if len(abstract) > 50:
            return abstract
    except Exception as e:
        print(f"    ⚠️  DuckDuckGo: {e}")
    return ""


def enriquecer_evento(evento):
    nombre_raw = evento.get("nombre", "")
    # Si el nombre resultó ser solo el nombre de la ticketera, recuperar desde URL slug
    if not nombre_raw or nombre_raw.lower().strip() in NOMBRES_TICKETERA:
        nombre_raw = nombre_desde_slug(evento.get("url", ""))
        evento["nombre"] = nombre_raw  # corregir también el campo almacenado
    nombre = limpiar_nombre_para_busqueda(nombre_raw)
    desc_original = evento.get("descripcion", "")
    print(f"    🔎 '{nombre[:55]}' ...")

    wiki = buscar_wikipedia(nombre)
    time.sleep(0.5)
    ddg = buscar_duckduckgo(nombre)
    time.sleep(0.5)

    bio = wiki or ddg

    if bio:
        sentences = re.split(r'(?<=[.!?])\s+', bio)
        truncated = ""
        for s in sentences:
            if len(truncated) + len(s) > 500:
                break
            truncated += s + " "
        bio = truncated.strip()

    desc_ext = desc_original if len(desc_original) >= 30 else (bio or "")

    evento["descripcion_extendida"] = desc_ext
    evento["bio_artista"] = bio

    if bio:
        print(f"      ✅ Bio ({len(bio)} chars)")
    else:
        print(f"      — Sin bio")

    return evento


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("=" * 55)
    print("  Scraper de eventos — Norte de Chile  v12")
    print("=" * 55)

    todos = []
    todos += scrape_ticketplus()
    todos += scrape_ticketpro()
    todos += scrape_puntoticket()
    todos += scrape_ticketmaster()
    todos += scrape_passline()
    todos += scrape_comediaticket()

    todos.sort(key=lambda e: e["fecha_iso"] if e["fecha_iso"] else "9999")

    print(f"\n📚 Enriqueciendo {len(todos)} eventos con Wikipedia y DuckDuckGo...")
    for i, evento in enumerate(todos):
        print(f"  [{i+1}/{len(todos)}]", end=" ")
        enriquecer_evento(evento)

    resultado = {
        "generado_en": datetime.now().isoformat(),
        "total_eventos": len(todos),
        "eventos": todos,
    }

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(resultado, f, ensure_ascii=False, indent=2)

    fuentes = {}
    for e in todos:
        fuentes[e["fuente"]] = fuentes.get(e["fuente"], 0) + 1

    con_imagen = sum(1 for e in todos if e["imagen_url"])
    con_fecha  = sum(1 for e in todos if e["fecha_iso"])
    con_bio    = sum(1 for e in todos if e.get("bio_artista"))

    print(f"\n{'=' * 55}")
    print(f"  Total           : {len(todos)} eventos")
    for fuente, count in sorted(fuentes.items()):
        print(f"  {fuente:<16}: {count}")
    print(f"  ---")
    print(f"  Con imagen      : {con_imagen}")
    print(f"  Con fecha       : {con_fecha}")
    print(f"  Con bio artista : {con_bio}")
    print(f"  Archivo         : '{OUTPUT_FILE}'")
    print(f"{'=' * 55}\n")


if __name__ == "__main__":
    main()
