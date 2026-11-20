"""Tests del soporte de torrents de widgets/cast-helper + widgets/cast-torrent (stdlib + node).
Ejecutar desde la raíz del repo:

    python3 -m unittest widgets/tests/test_cast_torrent.py

Los tests de rangos se omiten si no hay node o ~/.local/lib/cast-torrent/node_modules.
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import unittest
import unittest.mock
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
HELPER = RAIZ / "cast-helper"
SERVER = RAIZ / "cast-torrent" / "server.js"
INSTALADO = Path.home() / ".local/lib/cast-torrent"


def cargar():
    loader = importlib.machinery.SourceFileLoader("cast_helper", str(HELPER))
    spec = importlib.util.spec_from_loader("cast_helper", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class FuenteTorrent(unittest.TestCase):
    def setUp(self):
        self.h = cargar()

    def test_magnet_y_torrent_son_torrent(self):
        for s in ("magnet:?xt=urn:btih:abc", "/tmp/a.torrent", "https://x.org/a.TORRENT?token=1"):
            self.assertTrue(self.h.is_torrent_source(s), s)

    def test_otras_fuentes_no(self):
        for s in ("/tmp/a.mkv", "https://youtu.be/x", "", None):
            self.assertFalse(self.h.is_torrent_source(s), s)

    def test_cli_no_convierte_magnet_en_ruta(self):
        capturado = {}

        def falso_send(req):
            capturado.update(req)
            return {"ok": True}

        argv = ["cast-helper", "cast", "tele", "magnet:?xt=urn:btih:abc&dn=x"]
        with unittest.mock.patch.object(self.h, "send", falso_send), \
                unittest.mock.patch("sys.argv", argv), \
                unittest.mock.patch.object(self.h, "ensure_desktop_env"):
            self.h.main()
        self.assertEqual(capturado["source"], "magnet:?xt=urn:btih:abc&dn=x")

    def test_urls_locales_stremio(self):
        for s in (
            "http://127.0.0.1:11470/abc/0",
            "http://localhost:11470/abc/0",
            "http://192.168.1.20:11470/abc/0",
        ):
            self.assertTrue(self.h.is_local_stream_url(s), s)
        for s in ("https://youtu.be/x", "http://example.com/video.mp4", "magnet:?xt=urn:btih:abc", ""):
            self.assertFalse(self.h.is_local_stream_url(s), s)


@unittest.skipUnless(shutil.which("node") and (INSTALADO / "node_modules").is_dir(),
                     "falta node o ~/.local/lib/cast-torrent/node_modules")
class RangosHTTP(unittest.TestCase):
    """parseRange de server.js (RFC 7233) con total = 1000 bytes."""

    def rango(self, header):
        js = f"const {{parseRange}}=require({json.dumps(str(SERVER))});" \
             f"console.log(JSON.stringify(parseRange({json.dumps(header)},1000)))"
        r = subprocess.run(["node", "-e", js], capture_output=True, text=True,
                           env={**os.environ, "NODE_PATH": str(INSTALADO / "node_modules")})
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def test_normal(self):
        self.assertEqual(self.rango("bytes=10-19"), {"start": 10, "end": 19})

    def test_abierto(self):
        self.assertEqual(self.rango("bytes=990-"), {"start": 990, "end": 999})

    def test_sufijo(self):
        self.assertEqual(self.rango("bytes=-500"), {"start": 500, "end": 999})

    def test_sufijo_mayor_que_el_archivo(self):
        self.assertEqual(self.rango("bytes=-5000"), {"start": 0, "end": 999})

    def test_fin_pasado_el_eof_se_recorta(self):
        self.assertEqual(self.rango("bytes=900-999999"), {"start": 900, "end": 999})

    def test_inicio_fuera_de_rango(self):
        self.assertEqual(self.rango("bytes=1000-"), {"unsatisfiable": True})

    def test_cabecera_ilegible_sirve_entero(self):
        self.assertIsNone(self.rango("basura"))


if __name__ == "__main__":
    unittest.main()
