"""Tests de widgets/display-mode (solo stdlib). Desde la raíz del repo:

    python3 -m unittest widgets/tests/test_display_mode.py
"""
import importlib.machinery
import importlib.util
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "display-mode"
loader = importlib.machinery.SourceFileLoader("display_mode", str(HELPER))
spec = importlib.util.spec_from_loader("display_mode", loader)
dm = importlib.util.module_from_spec(spec)
loader.exec_module(dm)

INT = {"name": "eDP-2", "modes": ["1920x1080@144.00Hz", "1920x1080@60.00Hz"], "scale": 1}
HDMI = {"name": "HDMI-A-1", "modes": ["1920x1080@60.00Hz", "1920x1080@59.94Hz"], "scale": 1}
TV4K = {"name": "DP-3", "modes": ["3840x2160@60.00Hz", "3840x2160@30.00Hz", "1920x1080@120.00Hz"], "scale": 2}


class PickMode(unittest.TestCase):
    def test_nunca_inventa_frecuencias(self):
        self.assertEqual(dm.pick_mode(HDMI["modes"])[0], "1920x1080@60.00")

    def test_respeta_el_objetivo(self):
        self.assertEqual(dm.pick_mode(INT["modes"], 60)[0], "1920x1080@60.00")
        self.assertEqual(dm.pick_mode(INT["modes"], 144)[0], "1920x1080@144.00")

    def test_resolucion_nativa_de_una_tele_4k(self):
        self.assertEqual(dm.pick_mode(TV4K["modes"])[0], "3840x2160@60.00")

    def test_sin_modos_usa_preferred(self):
        self.assertEqual(dm.pick_mode([])[0], "preferred")


class Plan(unittest.TestCase):
    def test_extender_encadena_con_escala(self):
        s = dm.plan("extend", INT, [HDMI, TV4K], 60)
        self.assertEqual([x["position"] for x in s], ["0x0", "1920x0", "3840x0"])
        self.assertEqual(s[2]["scale"], 2)

    def test_espejo_y_limpieza(self):
        s = dm.plan("mirror", INT, [HDMI], 60)
        self.assertEqual(s[1]["mirror"], "eDP-2")
        self.assertEqual(dm.plan("extend", INT, [HDMI], 60)[1]["mirror"], "")

    def test_enciende_antes_de_apagar(self):
        s = dm.plan("external", INT, [HDMI], 60)
        self.assertFalse(s[0].get("disabled"))
        self.assertTrue(s[-1]["disabled"])
        s = dm.plan("laptop", INT, [HDMI], 60)
        self.assertFalse(s[0].get("disabled"))

    def test_sin_externo_no_apaga_el_portatil(self):
        for mode in ("external", "extend", "mirror"):
            with self.assertRaises(ValueError):
                dm.plan(mode, INT, [], 60)
        self.assertEqual(len(dm.plan("laptop", INT, [], 60)), 1)


class Estado(unittest.TestCase):
    @staticmethod
    def mon(**raw):
        return {"name": "x", "modes": [], "scale": 1, "raw": raw}

    def test_modos(self):
        i, e = self.mon(), self.mon()
        self.assertEqual(dm.current_mode(i, [e]), "extend")
        self.assertEqual(dm.current_mode(i, [self.mon(mirrorOf="0")]), "mirror")
        self.assertEqual(dm.current_mode(i, [self.mon(disabled=True)]), "laptop")
        self.assertEqual(dm.current_mode(self.mon(disabled=True), [e]), "external")
        self.assertEqual(dm.current_mode(i, []), "laptop")


if __name__ == "__main__":
    unittest.main()
