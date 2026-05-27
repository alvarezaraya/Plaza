"""
scraper_eventos.py  v16
======================
Extrae eventos culturales con imagen y descripción desde TODO Chile:
  - Ticketplus.cl       (todas las regiones de Chile)
  - Ticketpro.cl        (todo Chile — sin filtro de ciudad)
  - PuntoTicket.com     (todo Chile — /todos + /evento/)
  - Ticketmaster.cl     (filtra por texto en tarjeta; anti-bot)
  - Passline.com        (playwright — ciudades principales)
  - ComediaTicket.cl    (playwright — todos los shows de humor)
  - EsquinaRetornable.cl (cine arte Antofagasta — WordPress)
  - CulturaAntofagasta.cl (RSS WordPress — Corporación Municipal)
  - CulturaIquique.cl   (RSS WordPress — Orquesta Regional Tarapacá)

Requisitos:
    pip install requests beautifulsoup4
    pip install playwright && python3 -m playwright install chromium

Uso:
    python3 scraper_eventos.py
"""

import json
import re
import time
import warnings
from datetime import datetime

import requests
from bs4 import BeautifulSoup, XMLParsedAsHTMLWarning

# Los feeds RSS son XML; suprimir el warning al parsearlos con html.parser
warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)

# ── Configuración ────────────────────────────────────────────────────────────

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/124.0.0.0 Safari/537.36"
    )
}

# Términos de búsqueda (lowercase) — todas las comunas de Chile (usados para DETECCIÓN, no como filtro)
CIUDADES_OBJETIVO = [
    # Arica y Parinacota
    "arica", "camarones", "putre", "general lagos",
    # Tarapacá
    "iquique", "alto hospicio", "pozo almonte", "camiña", "camina",
    "colchane", "huara", "pica",
    # Antofagasta
    "antofagasta", "mejillones", "sierra gorda", "taltal", "calama",
    "ollagüe", "ollague", "san pedro de atacama", "tocopilla",
    "maría elena", "maria elena",
    # Atacama
    "copiapó", "copiapo", "caldera", "tierra amarilla",
    "chañaral", "chanaral", "diego de almagro", "vallenar",
    "alto del carmen", "freirina", "huasco",
    # Coquimbo
    "la serena", "coquimbo", "andacollo", "la higuera", "ovalle",
    "combarbalá", "combarbala", "monte patria", "punitaqui", "río hurtado",
    "illapel", "canela", "los vilos", "salamanca",
    # Valparaíso
    "valparaíso", "valparaiso", "viña del mar", "vina del mar",
    "quilpué", "quilpue", "villa alemana", "concón", "concon",
    "quillota", "calera", "hijuelas", "la cruz", "nogales",
    "san antonio", "cartagena", "el quisco", "el tabo", "algarrobo",
    "los andes", "san esteban", "calle larga", "rinconada",
    "san felipe", "putaendo", "santa maría", "panquehue", "llaillay",
    "casablanca", "juan fernández", "isla de pascua",
    # O'Higgins
    "rancagua", "graneros", "mostazal", "codegua", "machalí",
    "machali", "olivar", "requínoa", "rengo", "malloa", "quinta de tilcoco",
    "san vicente", "pichidegua", "las cabras", "peumo", "pichilemu",
    "litueche", "la estrella", "marchigüe", "marchigue", "navidad",
    "santa cruz", "chimbarongo", "nancagua", "palmilla", "peralillo",
    "placilla", "lolol", "pumanque", "san fernando", "chépica",
    # Maule
    "talca", "constitución", "constitucion", "curicó", "curico",
    "linares", "molina", "san clemente", "pelarco", "maule",
    "curepto", "sagrada familia", "teno", "romeral", "río claro",
    "retiro", "colbún", "colbun", "longaví", "longavi", "parral",
    "cauquenes", "pelluhue", "chanco", "vichuquén", "vichiquén",
    "hualañé", "rauco", "licantén",
    # Ñuble
    "chillán", "chillan", "chillán viejo", "san carlos", "ñiquén",
    "niquén", "san fabián", "san nicolás", "san nicolas", "bulnes",
    "quillón", "quillon", "el carmen", "pemuco", "yungay", "pinto",
    "coihueco", "san ignacio", "quinchamalí",
    # Biobío
    "concepción", "concepcion", "talcahuano", "penco", "hualqui",
    "florida", "santa juana", "coronel", "lota", "arauco",
    "lebu", "tirúa", "cañete", "contulmo", "curanilahue",
    "los álamos", "los alamos", "los ángeles", "los angeles",
    "santa bárbara", "quilaco", "mulchén", "mulchen", "nacimiento",
    "negrete", "laja", "san rosendo", "yumbel", "cabrero", "tucapel",
    "antuco", "chiguayante", "san pedro de la paz", "hualpén",
    # Araucanía
    "temuco", "padre las casas", "vilcún", "villarrica", "pucón",
    "pucon", "curarrehue", "melipeuco", "cunco", "freire", "pitrufquén",
    "gorbea", "loncoche", "villarrica", "nueva imperial", "teodoro schmidt",
    "carahue", "saavedra", "toltén", "angol", "renaico", "collipulli",
    "ercilla", "lumaco", "purén", "puren", "los sauces", "traiguén",
    "traiguen",
    # Los Ríos
    "valdivia", "mariquina", "lanco", "máfil", "mafil", "corral",
    "futrono", "lago ranco", "río bueno", "rio bueno", "la unión",
    "panguipulli", "los lagos",
    # Los Lagos
    "puerto montt", "puerto varas", "llanquihue", "frutillar",
    "los muermos", "maullín", "maullin", "calbuco", "cochamó",
    "cochamo", "osorno", "san pablo", "puerto octay", "purranque",
    "río negro", "rio negro", "san juan de la costa",
    "ancud", "castro", "chonchi", "curaco de vélez", "dalcahue",
    "puqueldón", "puqueldon", "queilén", "quellen", "quellón", "quellon",
    "quemchi", "quinchao", "coyhaique", "palena", "futaleufú", "futaleufu",
    "chaiten", "chaitén",
    # Aysén
    "coyhaique", "lago verde", "aysen", "aysén", "cisnes", "guaitecas",
    "cochrane", "o'higgins", "tortel",
    # Magallanes
    "punta arenas", "puerto natales", "torres del paine",
    "porvenir", "primavera", "timaukel", "cabo de hornos",
    # Metropolitana
    "santiago", "providencia", "las condes", "vitacura", "lo barnechea",
    "la reina", "peñalolén", "macul", "san joaquín", "san miguel",
    "pedro aguirre cerda", "lo espejo", "estación central", "cerrillos",
    "maipú", "maipu", "pudahuel", "lo prado", "cerro navia", "quinta normal",
    "renca", "conchalí", "conchal", "huechuraba", "recoleta", "independencia",
    "ñuñoa", "nunoa", "san bernardo", "el bosque", "la granja", "la cisterna",
    "el monte", "isla de maipo", "melipilla", "calera de tango", "colina",
    "lampa", "tiltil", "puente alto", "pirque", "san josé de maipo",
    "buin", "paine", "talagante", "padre hurtado", "peñaflor", "penarflor",
    "alhué", "curacaví",
]

# Nombre canónico por término de búsqueda (para normalizar la salida)
NOMBRE_CIUDAD = {
    # Norte Grande
    "arica": "Arica", "camarones": "Camarones", "putre": "Putre",
    "general lagos": "General Lagos",
    "iquique": "Iquique", "alto hospicio": "Alto Hospicio",
    "pozo almonte": "Pozo Almonte", "camiña": "Camiña", "camina": "Camiña",
    "colchane": "Colchane", "huara": "Huara", "pica": "Pica",
    "antofagasta": "Antofagasta", "mejillones": "Mejillones",
    "sierra gorda": "Sierra Gorda", "taltal": "Taltal", "calama": "Calama",
    "ollagüe": "Ollagüe", "ollague": "Ollagüe",
    "san pedro de atacama": "San Pedro de Atacama",
    "tocopilla": "Tocopilla",
    "maría elena": "María Elena", "maria elena": "María Elena",
    "copiapó": "Copiapó", "copiapo": "Copiapó",
    "caldera": "Caldera", "tierra amarilla": "Tierra Amarilla",
    "chañaral": "Chañaral", "chanaral": "Chañaral",
    "diego de almagro": "Diego de Almagro", "vallenar": "Vallenar",
    "alto del carmen": "Alto del Carmen", "freirina": "Freirina",
    "huasco": "Huasco",
    # Coquimbo
    "la serena": "La Serena", "coquimbo": "Coquimbo", "ovalle": "Ovalle",
    "illapel": "Illapel", "los vilos": "Los Vilos",
    # Valparaíso
    "valparaíso": "Valparaíso", "valparaiso": "Valparaíso",
    "viña del mar": "Viña del Mar", "vina del mar": "Viña del Mar",
    "quilpué": "Quilpué", "quilpue": "Quilpué",
    "villa alemana": "Villa Alemana", "concón": "Concón", "concon": "Concón",
    "quillota": "Quillota", "san antonio": "San Antonio",
    "los andes": "Los Andes", "san felipe": "San Felipe",
    "isla de pascua": "Isla de Pascua",
    # O'Higgins
    "rancagua": "Rancagua", "san fernando": "San Fernando",
    "pichilemu": "Pichilemu", "santa cruz": "Santa Cruz",
    "curicó": "Curicó", "curico": "Curicó",
    # Maule
    "talca": "Talca", "linares": "Linares", "constitución": "Constitución",
    "constitucion": "Constitución", "cauquenes": "Cauquenes",
    # Ñuble
    "chillán": "Chillán", "chillan": "Chillán",
    # Biobío
    "concepción": "Concepción", "concepcion": "Concepción",
    "talcahuano": "Talcahuano", "coronel": "Coronel", "lota": "Lota",
    "lebu": "Lebu", "los ángeles": "Los Ángeles", "los angeles": "Los Ángeles",
    # Araucanía
    "temuco": "Temuco", "villarrica": "Villarrica", "pucón": "Pucón",
    "pucon": "Pucón", "angol": "Angol",
    # Los Ríos
    "valdivia": "Valdivia",
    # Los Lagos
    "puerto montt": "Puerto Montt", "puerto varas": "Puerto Varas",
    "osorno": "Osorno", "frutillar": "Frutillar",
    "ancud": "Ancud", "castro": "Castro",
    # Aysén
    "coyhaique": "Coyhaique", "cochrane": "Cochrane",
    # Magallanes
    "punta arenas": "Punta Arenas", "puerto natales": "Puerto Natales",
    # Metropolitana
    "santiago": "Santiago", "providencia": "Providencia",
    "las condes": "Las Condes", "vitacura": "Vitacura",
    "lo barnechea": "Lo Barnechea", "la reina": "La Reina",
    "peñalolén": "Peñalolén", "ñuñoa": "Ñuñoa", "nunoa": "Ñuñoa",
    "maipú": "Maipú", "maipu": "Maipú",
    "san bernardo": "San Bernardo", "puente alto": "Puente Alto",
}

VENUES_CONOCIDOS = [
    # Antofagasta
    "teatro municipal de antofagasta", "enjoy antofagasta",
    "estadio regional antofagasta", "estadio sokol", "estadio sokol antofagasta",
    "sala andamios", "esquina retornable",
    # Iquique
    "teatro municipal de iquique",
    # Calama
    "teatro municipal de calama",
    # Santiago
    "teatro municipal de santiago", "teatro caupolicán", "caupolican",
    "movistar arena", "estadio nacional", "club chocolate",
    "anfiteatro cerrillos", "teatro la cúpula", "teatro mori",
    "teatro nescafé de las artes", "teatro oriente",
    # Valparaíso / Viña
    "enjoy viña del mar", "casino viña del mar",
    "teatro municipal de viña del mar",
    # Genérico
    "teatro municipal", "rock and soccer",
    "centro cultural estación", "club hípico", "gimnasio olímpico",
]

OUTPUT_FILE = "eventos.json"
PAUSA = 0.8
MAX_POR_REGION = 40   # Límite de eventos a detallar por región en Ticketplus

NOMBRES_TICKETERA = {"ticketplus", "ticketpro", "puntoticket", "ticketmaster", "passline", "comediaticket", "culturaantofagasta", "culturaiquique"}

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
    texto_lower = texto.lower()
    return any(re.search(rf'\b{re.escape(c)}\b', texto_lower) for c in CIUDADES_OBJETIVO)


def parsear_fecha(dia, mes_str):
    mes_str = mes_str.lower().strip()
    mes_num = MESES_ES.get(mes_str)
    if not mes_num:
        return "", ""
    anio = datetime.now().year
    ahora = datetime.now().date()
    try:
        fecha = datetime(anio, mes_num, int(dia)).date()
    except ValueError:
        return "", ""
    # Solo avanzar al año siguiente si el evento pasó hace más de 30 días.
    # Eventos recientes (≤30 días atrás) se retienen como fecha pasada para
    # ser descartados por el filtro del scraper que los originó.
    if fecha < ahora and (ahora - fecha).days > 30:
        anio += 1
        fecha = fecha.replace(year=anio)
    iso   = fecha.strftime("%Y-%m-%d")
    texto = f"{fecha.day} de {MESES_TEXTO[fecha.month]} de {fecha.year}"
    return iso, texto


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
    # Probar más largos primero para evitar que "arica" tape "camarones" etc.
    # Usar \b para no hacer match en substrings: "picante" no es "pica", "típica" tampoco.
    for c in sorted(CIUDADES_OBJETIVO, key=len, reverse=True):
        if re.search(rf'\b{re.escape(c)}\b', texto_lower):
            return NOMBRE_CIUDAD.get(c, c.title())
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
    nombre = re.sub(r"^Entradas\s+(?:para\s+)?", "", nombre, flags=re.IGNORECASE)
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
    for c in sorted(CIUDADES_OBJETIVO, key=len, reverse=True):
        nombre = re.sub(rf"\b{re.escape(c)}\b", "", nombre, flags=re.IGNORECASE)
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
    for c in sorted(CIUDADES_OBJETIVO, key=len, reverse=True):
        nombre = re.sub(rf"\b{re.escape(c)}\b", "", nombre, flags=re.IGNORECASE)
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

    REGIONES = [
        ("region-metropolitana",                                        "Santiago"),
        ("region-de-arica-y-parinacota",                                "Arica"),
        ("region-de-tarapaca",                                          "Iquique"),
        ("region-de-antofagasta",                                       "Antofagasta"),
        ("region-de-atacama",                                           "Copiapó"),
        ("region-de-coquimbo",                                          "La Serena"),
        ("region-de-valparaiso",                                        "Valparaíso"),
        ("region-del-libertador-general-bernardo-o-higgins",            "Rancagua"),
        ("region-del-maule",                                            "Talca"),
        ("region-de-nuble",                                             "Chillán"),
        ("region-del-bio-bio",                                          "Concepción"),
        ("region-de-la-araucania",                                      "Temuco"),
        ("region-de-los-rios",                                          "Valdivia"),
        ("region-de-los-lagos",                                         "Puerto Montt"),
        ("region-de-aysen",                                             "Coyhaique"),
        ("region-de-magallanes-y-de-la-antartica-chilena",              "Punta Arenas"),
    ]

    base = []
    vistos = set()

    for slug, ciudad_default in REGIONES:
        r = get(f"https://ticketplus.cl/states/{slug}")
        if not r:
            continue

        soup = BeautifulSoup(r.text, "html.parser")
        region_count = 0

        for a in soup.find_all("a", href=re.compile(r"/events/")):
            if region_count >= MAX_POR_REGION:
                break
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
            region_count += 1

            base.append({
                "texto_crudo": texto,
                "precio": precio,
                "ciudad_default": ciudad_default,
                "url": evento_url,
            })
        time.sleep(PAUSA)

    print(f"  → Obteniendo detalle de {len(base)} eventos...")
    eventos = []
    for i, b in enumerate(base):
        print(f"    [{i+1}/{len(base)}] {b['url'].split('/')[-1][:50]}...")
        og_title, imagen, desc, fecha_iso, fecha_texto, venue = extraer_detalle(b["url"])

        nombre_base = og_title or desc or b["texto_crudo"]
        if not venue:
            venue = detectar_venue(b["texto_crudo"])
        ciudad = detectar_ciudad(b["texto_crudo"]) or detectar_ciudad(f"{og_title} {desc}") or b["ciudad_default"]

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
        if not texto or len(texto) < 5:
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
    PuntoTicket — scrapea /todos sin filtro de ciudad (todo Chile).
    Los eventos viven en /evento/[slug]. Se excluyen solo páginas de nav/sistema.
    """
    print("\n🔍 PuntoTicket.com ...")
    r = get("https://www.puntoticket.com/todos")
    if not r:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    base = []
    vistos = set()

    # Páginas de sistema que no son eventos
    excluir = ["musica", "deportes", "teatro", "familia", "especiales",
               "todos", "Account", "Cliente", "paginas", "#"]

    for a in soup.find_all("a", href=re.compile(r"/evento/")):
        href = a.get("href", "")
        texto = limpiar(a.get_text(" "))

        if href.startswith("/"):
            evento_url = f"https://www.puntoticket.com{href}"
        elif href.startswith("https://www.puntoticket.com"):
            evento_url = href
        else:
            continue

        if any(x in href for x in excluir):
            continue
        if len(texto) < 4:
            continue
        if evento_url in vistos:
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
    NOTA: /buscar?q=... devuelve lista genérica (anti-bot), no filtra por ciudad.
    Se hace una búsqueda general desde la home y se incluyen todos los eventos,
    usando JSON-LD para detectar ciudad. Los eventos sin ciudad detectable quedan
    etiquetados con "Chile" y son visibles sin filtro de ciudad en la app.
    """
    print("\n🔍 Ticketmaster.cl ...")
    base = []
    vistos = set()

    # Scrape la página principal + búsqueda genérica (devuelve lo mismo)
    for url in ["https://www.ticketmaster.cl/", "https://www.ticketmaster.cl/buscar?q="]:
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

            texto = limpiar(a.get_text(" "))
            vistos.add(evento_url)
            ciudad_det = detectar_ciudad(texto) or ""
            base.append({"texto_crudo": texto, "ciudad_busqueda": ciudad_det, "url": evento_url})
        time.sleep(PAUSA)

    print(f"  → Obteniendo detalle de {len(base)} eventos...")
    eventos = []
    for i, b in enumerate(base):
        print(f"    [{i+1}/{len(base)}] {b['url'].split('/')[-1][:50]}...")
        r = get(b["url"])
        if not r:
            continue
        soup = BeautifulSoup(r.text, "html.parser")

        ciudad_jsonld = extraer_ciudad_jsonld(soup)
        todo_texto = f"{ciudad_jsonld} {b['texto_crudo']}".lower()

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

        nombre_base = og_title or desc or b["texto_crudo"]
        if not venue:
            venue = detectar_venue(todo_texto)
        ciudad = detectar_ciudad(ciudad_jsonld) or detectar_ciudad(todo_texto) or b["ciudad_busqueda"] or "Chile"

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

    # Passline redirige a home.passline.com (landing page sin eventos públicos).
    # Las URLs /ciudad/[slug] devuelven 403 con requests y no cargan eventos
    # con playwright. Se intenta desde la home principal como único punto de entrada.
    urls_ciudad = [
        ("Chile", "https://www.passline.com/"),
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

    # Rutas de sistema a excluir (comparación exacta, no prefijo)
    EXCLUIR_EXACTAS = {"/shop/faq", "/shop/terms", "/shop/post_with_us", "/home", "/shop/home", "/"}

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
                    from urllib.parse import urlparse
                    path = urlparse(href).path
                else:
                    continue

                # Quitar query-string/hash del path para comparación
                path_clean = path.split("?")[0].split("#")[0].rstrip("/") or "/"

                if full_url in vistos or len(texto) < 3:
                    continue
                # Excluir solo rutas de sistema exactas (no sub-rutas de eventos)
                if path_clean in EXCLUIR_EXACTAS:
                    continue
                if path_clean in ("", "") or re.match(r"^/\?", path):
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

        # Fecha: og:description, og:title, luego texto del card
        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(og_title)
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


# ── Scraper 7: Esquina Retornable ───────────────────────────────────────────

def scrape_esquinaretornable():
    """
    Esquina Retornable — cine arte en Antofagasta.
    Solo raspa el homepage. Estructura por película (icon-list vertical):
      ítem 0: título (con año entre paréntesis o tras guión)
      ítem 1: fecha  "DD de MES / HH:MM hrs."
      ítem 2: ciclo de cine
      ítem 3: director  "Dir. Nombre"
      ítem 4: sinopsis
    Se descartan eventos sin fecha.
    """
    print("\n🔍 EsquinaRetornable.cl (homepage) ...")

    BASE   = "https://esquinaretornable.cl"
    VENUE  = "Esquina Retornable"
    CIUDAD = "Antofagasta"
    url    = f"{BASE}/"

    headers_er = {
        **HEADERS,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "es-CL,es;q=0.9,en;q=0.8",
        "Referer": "https://www.google.com/",
    }

    # Primer ítem es fecha/día → lista sin título válido (se descarta)
    date_first_re = re.compile(
        r'^(lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo|\d{1,2}\s+de\s|\d{1,2}\s+de\s+[a-z])',
        re.I
    )
    # Año al final del título: "(1991)", "[2025]", "- 2025", "– 2025"
    year_re = re.compile(r'\s*[\(\[]\d{4}[\)\]]\s*$|\s*[-–—]\s*\d{4}\s*$')

    try:
        r = requests.get(url, headers=headers_er, timeout=15)
        r.raise_for_status()
    except requests.RequestException as e:
        print(f"  ⚠️  {url} → {e}")
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    eventos = []
    seen    = set()

    # Detener antes de secciones de archivo ("ya exhibidas", etc.)
    stop_node = None
    for heading in soup.find_all(["h1", "h2", "h3", "h4"]):
        if re.search(r"ya exhibid|anteriores|archivo", heading.get_text(), re.I):
            stop_node = heading
            break

    def _antes_del_corte(tag):
        return not (stop_node and tag.find_previous(lambda t: t is stop_node))

    def _imagen_en_container(tag):
        """Busca la primera imagen de wp-content/uploads dentro de tag."""
        for img in tag.find_all("img"):
            src = (img.get("src") or img.get("data-src")
                   or img.get("data-lazy-src") or "")
            if "wp-content/uploads" in src:
                return src.split("?")[0]
        return ""

    def _ticket_url_en(tag):
        for a in tag.find_all("a", href=True):
            href = a.get("href", "")
            text = a.get_text(strip=True).lower()
            if any(k in text for k in ("inscripci", "comprar", "ticket", "reserva")):
                return href
            if any(k in href for k in ("passline", "docs.google", "forms.gle", "eventbrite")):
                return href
        return url

    # Cada película tiene su propio elementor-icon-list-items (no inline).
    # Estructura esperada: [título, fecha, ciclo, director, sinopsis]
    for ul in soup.find_all(
        "ul",
        class_=lambda c: c and
            "elementor-icon-list-items" in (c if isinstance(c, str) else " ".join(c)) and
            "elementor-inline-items"    not in (c if isinstance(c, str) else " ".join(c))
    ):
        if not _antes_del_corte(ul):
            continue

        items = [
            limpiar(li.get_text(" ", strip=True))
            for li in ul.find_all("li")
            if li.get_text(strip=True)
        ]
        if len(items) < 2:
            continue

        # Descartar listas que empiezan con fecha (sin título de película)
        if date_first_re.match(items[0]):
            continue

        title = year_re.sub("", items[0]).strip()
        if not title or title in seen or len(title) < 3:
            continue

        # Fecha: "20 de mayo / 20:00 hrs." → tomar parte antes de "/"
        date_raw = items[1].split("/")[0].strip()
        fecha_iso, fecha_texto = extraer_fecha_de_texto(date_raw)
        if not fecha_iso:
            continue  # Evento sin fecha → ignorar
        try:
            from datetime import date as _date
            if datetime.strptime(fecha_iso, "%Y-%m-%d").date() < _date.today():
                continue  # Evento ya pasado → ignorar
        except ValueError:
            pass

        seen.add(title)

        ciclo    = items[2].strip() if len(items) > 2 else ""
        director = items[3].strip() if len(items) > 3 else ""
        sinopsis = items[4].strip() if len(items) > 4 else ""

        # descripcion = "Ciclo · Dir. Nombre"  (usado como subtítulo en la app)
        desc_parts = [p for p in [ciclo, director] if p]
        descripcion = " · ".join(desc_parts)

        # Imagen: está en el contenedor e-con-full 3 niveles sobre el ul
        # ul → widget-container → widget-div → e-con-full (tiene el póster)
        container = ul.parent.parent.parent if ul.parent and ul.parent.parent else None
        imagen = _imagen_en_container(container) if container else ""

        # URL de ticket en el mismo contenedor
        ticket_url = (_ticket_url_en(container) if container else url) or url

        nombre = limpiar_nombre(title, venue=VENUE, ciudad=CIUDAD)
        if not nombre:
            continue

        eventos.append({
            "fuente":                "EsquinaRetornable",
            "nombre":                nombre,
            "venue":                 VENUE,
            "descripcion":           descripcion,
            "descripcion_extendida": sinopsis,
            "fecha_iso":             fecha_iso,
            "fecha_texto":           fecha_texto,
            "precio_desde_clp":      "",
            "ciudad":                CIUDAD,
            "imagen_url":            imagen,
            "url":                   ticket_url,
        })

    print(f"  ✅ {len(eventos)} eventos")
    return eventos


# ── Scraper 8: CulturaAntofagasta RSS ───────────────────────────────────────

def scrape_cultura_antofagasta():
    """
    Corporación Municipal de Cultura de Antofagasta — feed RSS WordPress.
    Cada ítem es una noticia/evento; se filtra por fecha en el texto.
    """
    print("\n🔍 CulturaAntofagasta.cl (RSS) ...")
    FEED = "https://culturaantofagasta.cl/feed/"
    CIUDAD = "Antofagasta"

    r = get(FEED)
    if not r:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    items = soup.find_all("item")
    print(f"  → {len(items)} ítems en feed")

    eventos = []
    ahora = datetime.now().date()

    for item in items:
        title_tag = item.find("title")
        link_tag  = item.find("link")
        desc_tag  = item.find("description")

        if not title_tag or not link_tag:
            continue

        nombre_raw = limpiar(title_tag.get_text())
        url        = (link_tag.next_sibling or "").strip()
        if not url:
            url = link_tag.get_text(strip=True)

        desc_html  = desc_tag.get_text(" ", strip=True) if desc_tag else ""
        desc_clean = limpiar(re.sub(r"<[^>]+>", " ", desc_html))

        # Extraer fecha del título o descripción
        fecha_iso, fecha_texto = extraer_fecha_de_texto(nombre_raw)
        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(desc_clean)

        # Si no hay fecha o ya pasó → saltar
        if fecha_iso:
            try:
                if datetime.strptime(fecha_iso, "%Y-%m-%d").date() < ahora:
                    continue
            except ValueError:
                pass

        # Imagen: og:image desde la URL del post (solo si hay fecha — vale la pena)
        imagen = ""
        if fecha_iso and url:
            r2 = get(url)
            if r2:
                s2 = BeautifulSoup(r2.text, "html.parser")
                tag = s2.find("meta", property="og:image")
                if tag and tag.get("content"):
                    imagen = tag["content"].strip()
                # Refinar descripción con og:description si disponible
                tag2 = s2.find("meta", property="og:description")
                if tag2 and tag2.get("content"):
                    desc_clean = limpiar(tag2["content"])
            time.sleep(PAUSA)

        nombre = limpiar_nombre(nombre_raw, ciudad=CIUDAD)
        if not nombre:
            continue

        eventos.append({
            "fuente":           "CulturaAntofagasta",
            "nombre":           nombre,
            "venue":            "Corporación Municipal de Cultura",
            "descripcion":      desc_clean[:300],
            "fecha_iso":        fecha_iso,
            "fecha_texto":      fecha_texto,
            "precio_desde_clp": "",
            "ciudad":           CIUDAD,
            "imagen_url":       imagen,
            "url":              url,
        })

    print(f"  ✅ {len(eventos)} eventos")
    return eventos


# ── Scraper 9: CulturaIquique RSS ───────────────────────────────────────────

def scrape_cultura_iquique():
    """
    Corporación Cultural Municipal de Iquique — feed RSS WordPress.
    Contiene principalmente conciertos de la Orquesta Regional de Tarapacá.
    """
    print("\n🔍 CulturaIquique.cl (RSS) ...")
    FEED   = "https://culturaiquique.cl/feed/"
    CIUDAD = "Iquique"

    r = get(FEED)
    if not r:
        return []

    soup = BeautifulSoup(r.text, "html.parser")
    items = soup.find_all("item")
    print(f"  → {len(items)} ítems en feed")

    eventos = []
    ahora = datetime.now().date()

    for item in items:
        title_tag = item.find("title")
        link_tag  = item.find("link")
        desc_tag  = item.find("description")

        if not title_tag or not link_tag:
            continue

        nombre_raw = limpiar(title_tag.get_text())
        url        = (link_tag.next_sibling or "").strip()
        if not url:
            url = link_tag.get_text(strip=True)

        desc_html  = desc_tag.get_text(" ", strip=True) if desc_tag else ""
        desc_clean = limpiar(re.sub(r"<[^>]+>", " ", desc_html))

        # Extraer fecha del título ("29 de mayo: Concierto de Temporada")
        fecha_iso, fecha_texto = extraer_fecha_de_texto(nombre_raw)
        if not fecha_iso:
            fecha_iso, fecha_texto = extraer_fecha_de_texto(desc_clean)

        if fecha_iso:
            try:
                if datetime.strptime(fecha_iso, "%Y-%m-%d").date() < ahora:
                    continue
            except ValueError:
                pass

        # Imagen desde og:image del post
        imagen = ""
        if url:
            r2 = get(url)
            if r2:
                s2 = BeautifulSoup(r2.text, "html.parser")
                tag = s2.find("meta", property="og:image")
                if tag and tag.get("content"):
                    imagen = tag["content"].strip()
                tag2 = s2.find("meta", property="og:description")
                if tag2 and tag2.get("content"):
                    desc_clean = limpiar(tag2["content"])
            time.sleep(PAUSA)

        nombre = limpiar_nombre(nombre_raw, ciudad=CIUDAD)
        if not nombre:
            continue

        eventos.append({
            "fuente":           "CulturaIquique",
            "nombre":           nombre,
            "venue":            "Corporación Cultural Municipal de Iquique",
            "descripcion":      desc_clean[:300],
            "fecha_iso":        fecha_iso,
            "fecha_texto":      fecha_texto,
            "precio_desde_clp": "",
            "ciudad":           CIUDAD,
            "imagen_url":       imagen,
            "url":              url,
        })

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
    print("  Scraper de eventos — Todo Chile  v16")
    print("=" * 55)

    todos = []
    todos += scrape_ticketplus()
    todos += scrape_ticketpro()
    todos += scrape_puntoticket()
    todos += scrape_ticketmaster()
    todos += scrape_passline()
    todos += scrape_comediaticket()
    todos += scrape_esquinaretornable()
    todos += scrape_cultura_antofagasta()
    todos += scrape_cultura_iquique()

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
