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


class TestExtraerFechaDeTexto(unittest.TestCase):
    def test_con_de(self):
        iso, _ = s.extraer_fecha_de_texto("La función es el 20 de marzo en el teatro")
        self.assertTrue(iso.endswith("-03-20"), iso)

    def test_sin_de(self):
        iso, _ = s.extraer_fecha_de_texto("Concierto 5 julio gran noche")
        self.assertTrue(iso.endswith("-07-05"), iso)

    def test_sin_fecha(self):
        self.assertEqual(s.extraer_fecha_de_texto("Sin fecha por confirmar"), ("", ""))


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
    def test_fuente_cayo_a_cero(self):
        probs = s.verificar_salud({"A": 10, "B": 0}, {"A": 10, "B": 5}, 10, 15)
        self.assertTrue(any("B" in p for p in probs))

    def test_caida_global(self):
        probs = s.verificar_salud({"A": 5}, {"A": 50}, 5, 50)
        self.assertTrue(any("Total" in p for p in probs))

    def test_sano(self):
        self.assertEqual(s.verificar_salud({"A": 50}, {"A": 48}, 50, 48), [])

    def test_fuente_nueva_no_es_problema(self):
        # Una fuente nueva (sin historia previa) no debe marcar problema.
        self.assertEqual(s.verificar_salud({"A": 10, "NUEVA": 3}, {"A": 10}, 13, 10), [])


class TestContarPorFuente(unittest.TestCase):
    def test_cuenta(self):
        eventos = [{"fuente": "A"}, {"fuente": "A"}, {"fuente": "B"}, {}]
        self.assertEqual(s._contar_por_fuente(eventos), {"A": 2, "B": 1, "?": 1})


if __name__ == "__main__":
    unittest.main(verbosity=2)
