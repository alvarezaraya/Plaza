# test_scraper.py
# Tests de las funciones puras de parsing del scraper (sin red ni playwright).
# Ejecutar: python3 test_scraper.py   (o: python3 -m pytest test_scraper.py)

import unittest

import scraper_eventos as s


class TestLimpiar(unittest.TestCase):
    def test_colapsa_espacios(self):
        self.assertEqual(s.limpiar("  hola   mundo \n cultural "), "hola mundo cultural")

    def test_vacio(self):
        self.assertEqual(s.limpiar("   "), "")


class TestDetectarCiudad(unittest.TestCase):
    def test_match_directo(self):
        self.assertEqual(s.detectar_ciudad("Gran concierto en Antofagasta"), "Antofagasta")

    def test_normaliza_a_canonico(self):
        # "valparaiso" sin tilde debe normalizar al nombre canónico con tilde.
        self.assertEqual(s.detectar_ciudad("show en valparaiso"), "Valparaíso")

    def test_sin_ciudad(self):
        self.assertEqual(s.detectar_ciudad("Un evento cualquiera"), "")

    def test_no_match_en_substring(self):
        # "típica" no debe disparar "pica"; el \b lo evita.
        self.assertEqual(s.detectar_ciudad("comida típica chilena"), "")


class TestEsCiudadObjetivo(unittest.TestCase):
    def test_positivo(self):
        self.assertTrue(s.es_ciudad_objetivo("Evento en Temuco hoy"))

    def test_negativo(self):
        self.assertFalse(s.es_ciudad_objetivo("Evento sin ubicación"))


class TestParsearFecha(unittest.TestCase):
    def test_fecha_valida(self):
        iso, texto = s.parsear_fecha("15", "enero")
        self.assertTrue(iso.endswith("-01-15"), iso)
        self.assertIn("15 de enero de", texto)

    def test_mes_invalido(self):
        self.assertEqual(s.parsear_fecha("15", "noviembrez"), ("", ""))

    def test_dia_invalido(self):
        self.assertEqual(s.parsear_fecha("32", "enero"), ("", ""))

    def test_ancla_usa_anio_del_post_sin_bump(self):
        # "24 de abril" en un post de abril 2026 → 2026-04-24, aunque ya pasó.
        from datetime import date
        iso, _ = s.parsear_fecha("24", "abril", fecha_ancla=date(2026, 4, 15))
        self.assertEqual(iso, "2026-04-24")

    def test_ancla_rollover_dic_a_ene(self):
        # Post de diciembre sobre un evento de enero → año siguiente.
        from datetime import date
        iso, _ = s.parsear_fecha("5", "enero", fecha_ancla=date(2026, 12, 20))
        self.assertEqual(iso, "2027-01-05")


class TestExtraerFechaDeTexto(unittest.TestCase):
    def test_con_de(self):
        iso, _ = s.extraer_fecha_de_texto("La función es el 20 de marzo en el teatro")
        self.assertTrue(iso.endswith("-03-20"), iso)

    def test_sin_de(self):
        iso, _ = s.extraer_fecha_de_texto("Concierto 5 julio gran noche")
        self.assertTrue(iso.endswith("-07-05"), iso)

    def test_sin_fecha(self):
        self.assertEqual(s.extraer_fecha_de_texto("Sin fecha por confirmar"), ("", ""))

    def test_anio_explicito(self):
        iso, _ = s.extraer_fecha_de_texto("La obra va el 24 de abril de 2026 en GAM")
        self.assertEqual(iso, "2026-04-24")

    def test_ancla_propaga_a_parsear(self):
        from datetime import date
        iso, _ = s.extraer_fecha_de_texto("24 de abril: Concierto", fecha_ancla=date(2026, 4, 15))
        self.assertEqual(iso, "2026-04-24")


class TestNombreDesdeSlug(unittest.TestCase):
    def test_quita_sufijo_id(self):
        url = "https://ticketplus.cl/events/gran-concierto-rock_x18hd"
        self.assertEqual(s.nombre_desde_slug(url), "Gran Concierto Rock")

    def test_sin_sufijo(self):
        url = "https://x.cl/e/festival-de-jazz"
        self.assertEqual(s.nombre_desde_slug(url), "Festival De Jazz")


class TestLimpiarNombre(unittest.TestCase):
    def test_quita_ciudad(self):
        out = s.limpiar_nombre("Gran Show Antofagasta", ciudad="Antofagasta")
        self.assertNotIn("Antofagasta", out)
        self.assertIn("Gran Show", out)

    def test_quita_precio(self):
        out = s.limpiar_nombre("Concierto Desde $15.000")
        self.assertNotIn("$", out)
        self.assertNotIn("15.000", out)


class TestLimpiarNombreParaBusqueda(unittest.TestCase):
    def test_quita_tour(self):
        self.assertEqual(s.limpiar_nombre_para_busqueda("Los Bunkers - Tour 2026"), "Los Bunkers")

    def test_primer_segmento(self):
        out = s.limpiar_nombre_para_busqueda("Mon Laferte - Gira Autopoiética - Movistar Arena")
        self.assertEqual(out, "Mon Laferte")


class TestVerificarSalud(unittest.TestCase):
    def test_fuente_grande_cayo_a_cero_es_critico(self):
        criticos, adv = s.verificar_salud({"A": 0}, {"A": 30}, 0, 30)
        self.assertTrue(any("A" in c for c in criticos))
        self.assertEqual(adv, [])

    def test_fuente_pequena_cayo_a_cero_es_advertencia(self):
        # Un feed RSS pequeño (9 < umbral) que cae a 0 no debe abortar el CI.
        criticos, adv = s.verificar_salud({"A": 50, "RSS": 0}, {"A": 50, "RSS": 9}, 50, 59)
        self.assertEqual(criticos, [])
        self.assertTrue(any("RSS" in a for a in adv))

    def test_caida_global_es_critica(self):
        criticos, adv = s.verificar_salud({"A": 5}, {"A": 50}, 5, 50)
        self.assertTrue(any("Total" in c for c in criticos))

    def test_sano(self):
        self.assertEqual(s.verificar_salud({"A": 50}, {"A": 48}, 50, 48), ([], []))

    def test_fuente_nueva_no_es_problema(self):
        # Una fuente nueva (sin historia previa) no debe marcar problema.
        self.assertEqual(
            s.verificar_salud({"A": 50, "NUEVA": 3}, {"A": 50}, 53, 50), ([], []))


class TestContarPorFuente(unittest.TestCase):
    def test_cuenta(self):
        eventos = [{"fuente": "A"}, {"fuente": "A"}, {"fuente": "B"}, {}]
        self.assertEqual(s._contar_por_fuente(eventos), {"A": 2, "B": 1, "?": 1})


class TestRssEsEvento(unittest.TestCase):
    def test_recopilacion_descartada(self):
        self.assertFalse(s._rss_es_evento(
            "Día del Patrimonio marca récord: más de 4 mil actividades en el 100% de las comunas",
            "", "2026-05-31"))

    def test_nota_de_prensa_descartada(self):
        self.assertFalse(s._rss_es_evento(
            "Rinden homenaje al legado del fallecido escritor", "", ""))

    def test_evento_con_fecha_se_mantiene(self):
        self.assertTrue(s._rss_es_evento("Concierto de Temporada", "", "2026-06-05"))

    def test_evento_sin_fecha_con_palabra_clave(self):
        self.assertTrue(s._rss_es_evento(
            "Ciclo de conciertos barrocos del Ensamble", "", ""))

    def test_sin_fecha_ni_senal_descartado(self):
        self.assertFalse(s._rss_es_evento("Estudian Geoglifos de Ariquilda", "", ""))

    def test_seremi_recopilacion_descartada(self):
        # Anuncio institucional/recopilación, aunque tenga fecha.
        self.assertFalse(s._rss_es_evento(
            "Seremi de las Culturas de La Araucanía invita a la comunidad a ser "
            "parte de la celebración del Día del Patrimonio", "", "2026-05-31"))

    def test_invita_a_concierto_se_mantiene(self):
        # "invita a la comunidad" en un evento real NO debe descartarse.
        self.assertTrue(s._rss_es_evento(
            "Orquesta Sinfónica invita a la comunidad a su concierto de gala", "", ""))


class TestFiltroRegional(unittest.TestCase):
    def test_ciudad_de_region(self):
        for c in ("Antofagasta", "calama", "San Pedro de Atacama", "TOCOPILLA"):
            self.assertTrue(s.es_ciudad_de_region(c), c)

    def test_ciudad_fuera(self):
        for c in ("Santiago", "Iquique", "Valparaíso"):
            self.assertFalse(s.es_ciudad_de_region(c), c)
            self.assertTrue(s.ciudad_fuera_de_region(c), c)

    def test_desconocida_no_se_descarta_temprano(self):
        # Vacío y "Chile" se resuelven tras geocodificar, no se descartan antes.
        self.assertFalse(s.ciudad_fuera_de_region(""))
        self.assertFalse(s.ciudad_fuera_de_region("Chile"))

    def test_filtrar_base(self):
        base = [
            {"ciudad": "Antofagasta", "url": "a"},
            {"ciudad": "Santiago", "url": "b"},
            {"ciudad": "", "url": "c"},
            {"ciudad_busqueda": "Temuco", "url": "d"},
        ]
        urls = [b["url"] for b in s.filtrar_base_por_region(base)]
        self.assertEqual(urls, ["a", "c"])


class TestCargarFuentesPrevias(unittest.TestCase):
    def _con_json(self, data):
        import json, tempfile, os
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f)
        try:
            return s.cargar_fuentes_previas(path)
        finally:
            os.unlink(path)

    def test_mismo_alcance_devuelve_conteos(self):
        prev = self._con_json({"region": s.REGION_SCOPE,
                               "eventos": [{"fuente": "A"}, {"fuente": "A"}]})
        self.assertEqual(prev, {"A": 2})

    def test_alcance_distinto_resetea_baseline(self):
        # JSON histórico nacional (sin marcador region) → baseline vacío,
        # para que el primer run regional no dispare la alerta de caída >50%.
        prev = self._con_json({"eventos": [{"fuente": "A"}] * 300})
        self.assertEqual(prev, {})

    def test_sin_archivo(self):
        self.assertEqual(s.cargar_fuentes_previas("/no/existe.json"), {})


class TestLimpiarNombreRss(unittest.TestCase):
    def test_preserva_mes_y_ciudad(self):
        n = s.limpiar_nombre_rss("Abril: Concierto de la Orquesta Sinfónica de Antofagasta")
        self.assertIn("Abril", n)
        self.assertIn("Antofagasta", n)

    def test_quita_prefijo_ticketera(self):
        self.assertEqual(
            s.limpiar_nombre_rss("Ticketplus - Concierto de Jazz"), "Concierto de Jazz")


if __name__ == "__main__":
    unittest.main(verbosity=2)
