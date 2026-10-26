"""Tests de widgets/gym-health (solo stdlib). Ejecutar desde la raíz del repo:

    python3 -m unittest widgets/tests/test_gym_health.py
"""
import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "gym-health"
SECRET = "s3cr3t-no-debe-salir"


def load_helper():
    loader = importlib.machinery.SourceFileLoader("gym_health", str(HELPER))
    spec = importlib.util.spec_from_loader("gym_health", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def day(d, steps=None, sleep=None, deep=None, workouts=(), habits=()):
    return {"date": d, "steps": steps, "sleep_h": sleep,
            "sleep_stages_min": ({"light": 100, "deep": deep} if deep is not None else None),
            "resting_hr": None, "workouts": list(workouts), "habits": list(habits)}


# El 2026-10-26 es lunes. Para probar el corte de la semana ISO se usa hoy = miércoles 21
# (semana desde el lunes 19, con un entreno el sábado 18 que NO cuenta).
SUMMARY = {
    "schema_version": "1.0",
    "last_sync": {"watch_google_health": {"cursor": "2026-10-26T16:00:38+01:00",
                                          "last_day_with_data": "2026-10-26"}},
    "goals": {"steps_per_day": 10000, "sleep_h": 7.5, "sessions_per_week": 4},
    "daily": [day("2026-10-18", 24913, workouts=["Sábado"]),
              day("2026-10-19", 6163, workouts=["Lunes"]),
              day("2026-10-20", 8161, 2.58, 24, workouts=["Día 1"]),
              day("2026-10-21", 4613, 5.95, 6),
              day("2026-10-22", 11213, 1.43, 19, workouts=["Día 2", "Cardio"]),
              day("2026-10-23", 660, 9.13, 65, habits=["creatina"]),
              day("2026-10-24", 1700, 7.75, 62),
              day("2026-10-25", 6919, 0.55),
              day("2026-10-26", 330, 4.97)],
}


class Handler(BaseHTTPRequestHandler):
    hits = 0
    mode = "ok"

    def do_GET(self):
        type(self).hits += 1
        if self.headers.get("Authorization") is None or self.mode == "401":
            self.send_response(401); self.end_headers(); return
        if self.mode == "500":
            self.send_response(500); self.end_headers(); return
        body = json.dumps(SUMMARY).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


class NormalizeTest(unittest.TestCase):
    def test_normalize(self):
        m = load_helper()
        from datetime import date
        out = m.normalize(SUMMARY, date(2026, 10, 26))
        self.assertEqual([d["date"] for d in out["days"]][0], "2026-10-20")
        self.assertEqual(len(out["days"]), 7)
        self.assertEqual(out["days"][-1]["steps"], 330)
        self.assertEqual(out["days"][0]["deepMin"], 24)
        self.assertIsNone(out["days"][-1]["deepMin"])
        self.assertEqual(out["days"][2]["workouts"], 2)
        self.assertEqual(out["days"][3]["habits"], ["creatina"])
        self.assertEqual(out["weekWorkouts"], 0)  # el 26 es lunes: la semana empieza hoy
        self.assertEqual(out["goal"], {"steps": 10000, "sleepH": 7.5, "sessionsPerWeek": 4})
        self.assertEqual(out["lastDayWithData"], "2026-10-26")

    def test_semana_iso_desde_el_lunes(self):
        m = load_helper()
        from datetime import date
        out = m.normalize(SUMMARY, date(2026, 10, 21))
        self.assertEqual(out["days"][0]["date"], "2026-10-15")
        self.assertEqual(out["weekWorkouts"], 2)  # lunes 19 + martes 20; el sábado 18 no

    def test_normalize_rellena_dias_que_faltan(self):
        m = load_helper()
        from datetime import date
        s = dict(SUMMARY, daily=[day("2026-10-26", 100)])
        out = m.normalize(s, date(2026, 10, 26))
        self.assertEqual(len(out["days"]), 7)
        self.assertIsNone(out["days"][0]["steps"])
        self.assertEqual(out["days"][-1]["steps"], 100)


class CliTest(unittest.TestCase):
    def setUp(self):
        Handler.hits, Handler.mode = 0, "ok"
        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.creds = self.dir / "credentials"
        self.url = f"http://127.0.0.1:{self.srv.server_port}"

    def tearDown(self):
        self.srv.shutdown()
        self.tmp.cleanup()

    def write_creds(self, mode=0o600):
        self.creds.write_text(f"machine 127.0.0.1 login instinct password {SECRET}\n")
        os.chmod(self.creds, mode)

    def run_helper(self, url=None):
        env = dict(os.environ, GYM_HEALTH_URL=url or self.url, GYM_HEALTH_CREDENTIALS=str(self.creds),
                   GYM_HEALTH_CACHE_DIR=str(self.dir / "cache"), GYM_HEALTH_TODAY="2026-10-26")
        p = subprocess.run([sys.executable, "-I", str(HELPER), "--json"], env=env,
                           capture_output=True, text=True, timeout=30)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertNotIn(SECRET, p.stdout + p.stderr)
        return json.loads(p.stdout)

    def cache_text(self):
        return "".join(f.read_text() for f in (self.dir / "cache").glob("*") if f.is_file())

    def test_sin_fichero(self):
        out = self.run_helper()
        self.assertEqual(out["status"], "nocreds")
        self.assertEqual(Handler.hits, 0)

    def test_permisos_abiertos(self):
        self.write_creds(0o644)
        out = self.run_helper()
        self.assertEqual(out["status"], "nocreds")
        self.assertIn("permisos", out["reason"])
        self.assertEqual(Handler.hits, 0)

    def test_ok_y_cache_fresca(self):
        self.write_creds()
        out = self.run_helper()
        self.assertEqual(out["status"], "ok")
        self.assertEqual(out["days"][-1]["steps"], 330)
        self.assertEqual(Handler.hits, 1)
        again = self.run_helper()
        self.assertEqual(again["status"], "ok")
        self.assertEqual(Handler.hits, 1)  # caché < 15 min: sin red
        self.assertNotIn(SECRET, self.cache_text())

    def test_401_no_reintenta_hasta_tocar_el_fichero(self):
        self.write_creds()
        Handler.mode = "401"
        self.assertEqual(self.run_helper()["status"], "auth")
        self.assertEqual(Handler.hits, 1)
        self.assertEqual(self.run_helper()["status"], "auth")
        self.assertEqual(Handler.hits, 1)  # bloqueado: cero reintentos
        Handler.mode = "ok"
        time.sleep(0.01)
        self.write_creds()  # Alberto corrige el fichero → cambia el mtime
        self.assertEqual(self.run_helper()["status"], "ok")
        self.assertEqual(Handler.hits, 2)

    def test_offline_con_cache(self):
        self.write_creds()
        self.run_helper()
        cache = self.dir / "cache" / "summary.json"
        d = json.loads(cache.read_text())
        d["fetchedAt"] = "2026-10-26T00:00:00+01:00"  # caché vieja → intenta la red
        cache.write_text(json.dumps(d))
        out = self.run_helper(url="http://127.0.0.1:9")  # puerto cerrado
        self.assertEqual(out["status"], "offline")
        self.assertEqual(out["days"][-1]["steps"], 330)
        self.assertEqual(out["fetchedAt"], "2026-10-26T00:00:00+01:00")

    def test_500(self):
        self.write_creds()
        Handler.mode = "500"
        out = self.run_helper()
        self.assertEqual(out["status"], "error")
        self.assertEqual(out["days"], [])


if __name__ == "__main__":
    unittest.main()
