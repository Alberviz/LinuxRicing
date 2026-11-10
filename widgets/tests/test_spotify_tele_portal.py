"""Tests de widgets/spotify-tele — integración con el portal agujero negro de la tele (Portals.qml).

Ejecutar:
    python3 -m unittest widgets/tests/test_spotify_tele_portal.py
"""
import argparse
import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HELPER = Path(__file__).resolve().parent.parent / "spotify-tele"


def cargar():
    loader = importlib.machinery.SourceFileLoader("spotify_tele", str(HELPER))
    spec = importlib.util.spec_from_loader("spotify_tele", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class TestSpotifyTelePortal(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="cast_portal"))
        self.salidas = self.tmp / "salidas.jsonl"
        self.env = mock.patch.dict(os.environ, {"CAST_SALIDAS": str(self.salidas)})
        self.env.start()
        self.mod = cargar()

    def tearDown(self):
        self.env.stop()

    def _lineas(self):
        if not self.salidas.exists():
            return []
        return [json.loads(line) for line in self.salidas.read_text(encoding="utf-8").splitlines() if line.strip()]

    def test_emit_tele_salida(self):
        self.mod.emit_tele_salida("enviando", "spotify", "Dakiti", {"artista": "Bad Bunny", "tele": "Tele Salón"})
        lineas = self._lineas()
        self.assertEqual(len(lineas), 1)
        self.assertEqual(lineas[0]["fase"], "enviando")
        self.assertEqual(lineas[0]["tipo"], "spotify")
        self.assertEqual(lineas[0]["nombre"], "Dakiti")
        self.assertEqual(lineas[0]["artista"], "Bad Bunny")
        self.assertEqual(lineas[0]["tele"], "Tele Salón")
        self.assertIn("ts", lineas[0])

    def test_cmd_pasar_tele_exito(self):
        a = argparse.Namespace(donde="tele", tele="Tele Salón")
        fake_res = {
            "ok": True,
            "ahora": {"cancion": "Yonaguni", "artista": "Bad Bunny", "dispositivo": "Tele Salón"}
        }
        with mock.patch.object(self.mod, "run_js", return_value=fake_res):
            res = self.mod.cmd_pasar(a)
        self.assertTrue(res["ok"])
        lineas = self._lineas()
        self.assertEqual(len(lineas), 2)
        self.assertEqual(lineas[0]["fase"], "enviando")
        self.assertEqual(lineas[0]["nombre"], "Spotify")
        self.assertEqual(lineas[1]["fase"], "ok")
        self.assertEqual(lineas[1]["nombre"], "Yonaguni")
        self.assertEqual(lineas[1]["artista"], "Bad Bunny")
        self.assertEqual(lineas[1]["tele"], "Tele Salón")

    def test_cmd_pasar_tele_error(self):
        a = argparse.Namespace(donde="tele", tele="Tele Salón")
        fake_res = {"ok": False, "error": "Spotify no ve la tele"}
        with mock.patch.object(self.mod, "run_js", return_value=fake_res):
            res = self.mod.cmd_pasar(a)
        self.assertFalse(res["ok"])
        lineas = self._lineas()
        self.assertEqual(len(lineas), 2)
        self.assertEqual(lineas[0]["fase"], "enviando")
        self.assertEqual(lineas[1]["fase"], "error")
        self.assertIn("no ve la tele", lineas[1]["mensaje"])

    def test_cmd_poner_tele_exito(self):
        a = argparse.Namespace(
            texto="Dakiti",
            tipo="cancion",
            donde="tele",
            tele="Tele Salón",
            aleatorio=None,
            desde_inicio=False,
            orden=None
        )
        fake_res = {
            "ok": True,
            "puesto": {"nombre": "Dakiti", "de": "Bad Bunny"},
            "ahora": {"cancion": "Dakiti", "artista": "Bad Bunny", "dispositivo": "Tele Salón"}
        }
        with mock.patch.object(self.mod, "run_js", return_value=fake_res):
            res = self.mod.cmd_poner(a)
        self.assertTrue(res["ok"])
        lineas = self._lineas()
        self.assertEqual(len(lineas), 2)
        self.assertEqual(lineas[0]["fase"], "enviando")
        self.assertEqual(lineas[0]["nombre"], "Dakiti")
        self.assertEqual(lineas[1]["fase"], "ok")
        self.assertEqual(lineas[1]["nombre"], "Dakiti")
        self.assertEqual(lineas[1]["artista"], "Bad Bunny")
        self.assertEqual(lineas[1]["tele"], "Tele Salón")

    def test_cmd_poner_pc_no_emite_portal_tele(self):
        a = argparse.Namespace(
            texto="Dakiti",
            tipo="cancion",
            donde="pc",
            tele="Tele Salón",
            aleatorio=None,
            desde_inicio=False,
            orden=None
        )
        fake_res = {"ok": True, "puesto": {"nombre": "Dakiti"}, "ahora": {}}
        with mock.patch.object(self.mod, "run_js", return_value=fake_res):
            res = self.mod.cmd_poner(a)
        self.assertTrue(res["ok"])
        self.assertEqual(self._lineas(), [])

    def test_cmd_cola_nueva_tele(self):
        a = argparse.Namespace(
            subcmd="nueva",
            canciones=["Dakiti", "Yonaguni"],
            donde="tele",
            tele="Tele Salón"
        )
        fake_res = {
            "ok": True,
            "reproduciendo": {"nombre": "Dakiti", "de": "Bad Bunny"},
            "encoladas": [{"nombre": "Yonaguni"}],
            "total": 2,
            "ahora": {"dispositivo": "Tele Salón"}
        }
        with mock.patch.object(self.mod, "run_js", return_value=fake_res):
            res = self.mod.cmd_cola(a)
        self.assertTrue(res["ok"])
        lineas = self._lineas()
        self.assertEqual(len(lineas), 2)
        self.assertEqual(lineas[0]["fase"], "enviando")
        self.assertEqual(lineas[0]["nombre"], "Dakiti")
        self.assertEqual(lineas[1]["fase"], "ok")
        self.assertIn("Dakiti (+1 en cola)", lineas[1]["nombre"])


if __name__ == "__main__":
    unittest.main()
