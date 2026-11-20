import importlib.machinery
import importlib.util
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load_script(name):
    path = str(ROOT / "widgets" / name)
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


tele = load_script("tele")


class TestTeleUnified(unittest.TestCase):
    def test_find_monitors_ignores_tablet_and_picks_syncmaster(self):
        mons = [
            {"name": "eDP-2", "description": "Laptop", "disabled": False},
            {"name": "Tablet", "description": "Virtual Tablet", "disabled": False},
            {"name": "HDMI-A-1", "description": "Samsung Electric Company SyncMaster H1AK500000", "disabled": False},
        ]
        with patch.object(tele, "hypr_json", return_value=mons):
            res = tele.find_monitors(tele.DEFAULT_CONFIG)
        self.assertEqual(res["laptop"]["name"], "eDP-2")
        self.assertEqual(res["hdmi"]["name"], "HDMI-A-1")
        self.assertTrue(res["hdmi_active"])
        self.assertIsNone(res["cast"])

    def test_find_monitors_detects_cast_virtual_without_hdmi(self):
        mons = [
            {"name": "eDP-2", "description": "Laptop", "disabled": False},
            {"name": "Tablet", "description": "Virtual Tablet", "disabled": False},
            {"name": "CAST-1", "description": "Headless", "disabled": False},
        ]
        with patch.object(tele, "hypr_json", return_value=mons):
            res = tele.find_monitors(tele.DEFAULT_CONFIG)
        self.assertIsNone(res["hdmi"])
        self.assertEqual(res["cast"]["name"], "CAST-1")

    def test_open_target_routes_video_to_chromecast_when_no_hdmi(self):
        mons = [{"name": "eDP-2", "description": "Laptop", "disabled": False}]
        cc = {"name": "Гостиная", "uuid": "uuid-1", "online": True}
        with patch.object(tele, "hypr_json", return_value=mons), \
             patch.object(tele, "find_chromecast", return_value=cc), \
             patch("subprocess.run") as mock_run:
            mock_run.return_value.returncode = 0
            ok = tele.open_target("/tmp/promo.mp4")
        self.assertTrue(ok)
        args = mock_run.call_args[0][0]
        self.assertIn("cast", args)
        self.assertIn("uuid-1", args)
        self.assertIn("/tmp/promo.mp4", args)

    def test_open_target_routes_everything_to_hdmi_when_connected(self):
        mons = [
            {"name": "eDP-2", "description": "Laptop", "disabled": False},
            {"name": "HDMI-A-1", "description": "Samsung Electric Company SyncMaster H1AK500000", "disabled": False},
        ]
        with patch.object(tele, "hypr_json", return_value=mons), \
             patch("subprocess.run") as mock_run:
            mock_run.return_value.returncode = 0
            ok = tele.open_target("http://localhost:5173")
        self.assertTrue(ok)
        args = mock_run.call_args[0][0]
        self.assertIn("open-target", args)
        self.assertIn("http://localhost:5173", args)


if __name__ == "__main__":
    unittest.main()
