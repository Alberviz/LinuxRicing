"""Tests de widgets/warp (solo stdlib). Ejecutar desde la raíz del repo:

    python3 -m unittest widgets/tests/test_warp.py
"""
import importlib.machinery
import importlib.util
import io
import json
import os
import tempfile
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

HELPER = Path(__file__).resolve().parent.parent / "warp"


def cargar():
    loader = importlib.machinery.SourceFileLoader("warp_cli", str(HELPER))
    spec = importlib.util.spec_from_loader("warp_cli", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class Base(unittest.TestCase):
    buscador = "walk"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="warp"))
        self.raiz = self.tmp / "home"
        self.raiz.mkdir()
        self.log = self.tmp / "olimpo.log"
        olimpo = self.tmp / "olimpo"
        olimpo.write_text(f"""#!/bin/sh
echo "$@" >> {self.log}
if [ "$2" = "--texto" ]; then cat >> {self.log}; echo; fi
echo '{{"ok":true,"id":"bnd_1","nombre":"x"}}'
""")
        olimpo.chmod(0o755)
        self.env = mock.patch.dict(os.environ, {"WARP_RAIZ": str(self.raiz), "WARP_OLIMPO": str(olimpo), "WARP_BUSCADOR": self.buscador,
                                                "WARP_SALIDAS": str(self.tmp / "salidas.jsonl")})
        self.env.start()
        self.w = cargar()

    def tearDown(self):
        self.env.stop()

    def hacer(self, rel, dias=0, datos=b"x"):
        p = self.raiz / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(datos)
        t = time.time() - dias * 86400
        os.utime(p, (t, t))
        return p

    def correr(self, *args):
        out = io.StringIO()
        with redirect_stdout(out):
            codigo = self.w.main([*args, "--json"])
        return codigo, json.loads(out.getvalue())

    def salidas(self):
        return [json.loads(l) for l in (self.tmp / "salidas.jsonl").read_text().splitlines()]


class Buscar(Base):
    def test_encuentra_sin_tildes_y_por_tipo(self):
        self.hacer("Universidad/Redes/Práctica 3 - Redes.pdf", dias=2)
        self.hacer("Universidad/Redes/practica3.docx", dias=1)
        self.hacer("Descargas/redes.png")
        c, d = self.correr("buscar", "el pdf de la practica de redes")
        self.assertEqual(c, 0)
        self.assertEqual([x["nombre"] for x in d["candidatos"]], ["Práctica 3 - Redes.pdf"])
        self.assertTrue(d["claro"])

    def test_varios_parecidos_no_es_claro(self):
        self.hacer("Documentos/factura luz enero.pdf", dias=40)
        self.hacer("Documentos/factura luz febrero.pdf", dias=10)
        c, d = self.correr("buscar", "factura luz")
        self.assertEqual(len(d["candidatos"]), 2)
        self.assertEqual(d["candidatos"][0]["nombre"], "factura luz febrero.pdf")  # la más reciente gana
        self.assertFalse(d["claro"])

    def test_ignora_ocultos_y_node_modules(self):
        self.hacer(".ssh/redes.pdf")
        self.hacer("proyecto/node_modules/redes.pdf")
        c, d = self.correr("buscar", "redes")
        self.assertEqual(d["candidatos"], [])

    def test_consulta_vacia(self):
        c, d = self.correr("buscar", "el de la")
        self.assertEqual(c, 1)
        self.assertIn("Dime algo", d["error"])


    def test_capturas_de_whatsapp_en_descargas(self):
        # caso real (16:06): «envía una de las capturas de WhatsApp que están en descargas» → .jpeg dentro de Descargas
        self.hacer("Descargas/WhatsApp Image 2026-11-07 at 20.39.01.jpeg", dias=2)
        self.hacer("Descargas/WhatsApp Image 2026-11-09 at 00.47.40.jpeg")
        self.hacer("Documentos/WhatsApp Image vieja.jpeg", dias=1)
        self.hacer("Descargas/factura.pdf")
        c, d = self.correr("buscar", "capturas de whatsapp", "--carpeta", "Descargas")
        self.assertEqual(c, 0)
        self.assertEqual([x["nombre"] for x in d["candidatos"]],
                         ["WhatsApp Image 2026-11-09 at 00.47.40.jpeg", "WhatsApp Image 2026-11-07 at 20.39.01.jpeg"])
        self.assertFalse(d["claro"])

    def test_listar_una_carpeta(self):
        for i in range(10):
            self.hacer(f"Descargas/f{i}.pdf", dias=i)
        self.hacer("Descargas/.oculto")
        self.hacer("Descargas/a medias.pdf.part")
        c, d = self.correr("listar", "descargas")
        self.assertEqual(c, 0)
        self.assertEqual(d["total"], 10)
        self.assertEqual([x["nombre"] for x in d["candidatos"]], [f"f{i}.pdf" for i in range(8)])
        self.assertFalse(self.log.exists())                       # listar nunca envía

    def test_listar_incluye_subcarpetas_solo_en_local(self):
        self.hacer("Documentos/informe.pdf")
        (self.raiz / "Documentos" / "Universidad").mkdir()
        (self.raiz / "Documentos" / ".privada").mkdir()
        c, d = self.correr("listar", "documentos")
        self.assertEqual(c, 0)
        self.assertEqual([x["nombre"] for x in d["candidatos"]], ["Universidad", "informe.pdf"])   # carpetas primero
        self.assertTrue(d["candidatos"][0]["carpeta"])
        self.assertNotIn("carpeta", d["candidatos"][1])
        c, d = self.correr("listar", "documentos", "--remoto")                                       # desde el móvil: solo archivos
        self.assertEqual([x["nombre"] for x in d["candidatos"]], ["informe.pdf"])

    def test_listar_remoto_no_entra_en_ocultas(self):
        self.hacer(".ssh/id_ed25519")
        c, d = self.correr("listar", str(self.raiz / ".ssh"), "--remoto")
        self.assertEqual((c, d["error"]), (1, "Esa ruta no se puede enviar desde el móvil."))


class BuscarConFd(Buscar):
    buscador = "fd"


class Remoto(Base):
    def test_remoto_no_puede_pedir_portapapeles_ni_captura(self):
        for accion in ("portapapeles", "seleccion", "captura", "texto", "rapido"):
            c, d = self.correr(accion, "--remoto")
            self.assertEqual(c, 1, accion)

    def test_remoto_rechaza_rutas_sensibles_o_fuera(self):
        claves = self.hacer("Documentos/servidor.key")
        oculto = self.hacer(".config/x.pdf")
        for ruta in (claves, oculto, Path("/etc/hostname")):
            c, d = self.correr("archivo", str(ruta), "--remoto")
            self.assertEqual((c, d["error"]), (1, "Esa ruta no se puede enviar desde el móvil."), ruta)
        self.assertFalse(self.log.exists())

    def test_remoto_envia_un_archivo_normal(self):
        p = self.hacer("Documentos/apuntes.pdf", datos=b"12345")
        c, d = self.correr("archivo", str(p), "--remoto", "--origen", "instinct")
        self.assertEqual(c, 0)
        self.assertEqual(d["enviado"]["nombre"], "apuntes.pdf")
        self.assertIn(f"enviar {p}", self.log.read_text())
        self.assertEqual([(s["fase"], s["origen"]) for s in self.salidas()], [("enviando", "instinct"), ("ok", "instinct")])


class Enviar(Base):
    def test_texto_por_stdin_va_a_olimpo_y_se_anuncia(self):
        with mock.patch("sys.stdin", io.StringIO("clave: hunter2\n")):
            c, d = self.correr("texto", "-", "--origen", "atajo")
        self.assertEqual((c, d["tipo"]), (0, "texto"))
        self.assertIn("enviar --texto -\nclave: hunter2", self.log.read_text())
        s = self.salidas()
        self.assertEqual(s[0]["fase"], "enviando")
        self.assertEqual(s[0]["fragmento"], "clave: hunter2\n")
        self.assertEqual(s[-1]["fase"], "ok")

    def test_texto_vacio(self):
        c, d = self.correr("texto", "   ")
        self.assertEqual(c, 1)

    def test_ultimo_de_una_carpeta(self):
        self.hacer("Descargas/viejo.pdf", dias=3)
        self.hacer("Descargas/nuevo.zip", dias=0)
        self.hacer("Descargas/.oculto", dias=0)
        c, d = self.correr("ultimo", "Descargas")
        self.assertEqual(d["enviado"]["nombre"], "nuevo.zip")

    def test_rapido_usa_el_portapapeles_y_si_no_la_seleccion(self):
        llamadas = []

        def leer(cmd):
            llamadas.append(cmd)
            if "--list-types" in cmd:
                return b"text/plain"
            return b"" if "--primary" not in cmd else b"subrayado"
        self.w.leer = leer
        c, d = self.correr("rapido")
        self.assertEqual(c, 0)
        self.assertIn("subrayado", self.log.read_text())

    def test_error_de_olimpo_se_anuncia(self):
        (self.tmp / "olimpo").write_text('#!/bin/sh\necho \'{"ok":false,"error":"La Pi no responde"}\'\n')
        c, d = self.correr("texto", "hola")
        self.assertEqual((c, d["error"]), (1, "La Pi no responde"))
        self.assertEqual(self.salidas()[-1]["fase"], "error")
        self.assertEqual(self.salidas()[-1]["mensaje"], "La Pi no responde")


if __name__ == "__main__":
    unittest.main()
