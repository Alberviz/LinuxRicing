"""Pruebas del cliente de Workspace contra un servidor MCP simulado (formato de texto real de
workspace-mcp). Nada toca Google ni la red.   python tests/mock_workspace.py"""
import json
import os
import stat
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
os.environ["LAURA_DATA"] = tempfile.mkdtemp()

CALLS: list = []
NOW = datetime.now().astimezone()
SOON = (NOW + timedelta(minutes=15)).isoformat(timespec="seconds")
TOOLS = [{"name": n, "inputSchema": {"properties": {"user_google_email": {}}}} for n in
         ("search_gmail_messages", "get_gmail_message_content", "get_events", "create_event")]

SEARCH = """Found 3 messages matching 'x':

  1. Message ID: m1
     Subject: Plazo de matrícula
     From: Secretaría <secretaria@uj.edu.pl>
     Date: Wed, 21 Oct 2026 08:00:00 +0200
     Labels: INBOX, UNREAD, CATEGORY_PRIMARY
     Web Link: https://mail.google.com/mail/u/0/#all/m1
     Thread ID: t1

  2. Message ID: m2
     Subject: Tu pedido ha sido enviado
     From: Amazon <envios@amazon.es>
     Date: Wed, 21 Oct 2026 09:00:00 +0200
     Labels: INBOX, UNREAD, CATEGORY_UPDATES
     Web Link: https://mail.google.com/mail/u/0/#all/m2
     Thread ID: t2

  3. Message ID: m3
     Subject: Hola Alberto
     From: Marta <marta@gmail.com>
     Date: Wed, 21 Oct 2026 10:00:00 +0200
     Labels: INBOX, UNREAD, CATEGORY_PRIMARY
     Web Link: https://mail.google.com/mail/u/0/#all/m3
     Thread ID: t3
"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_POST(self):
        d = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        m = d.get("method")
        if m == "notifications/initialized":
            self.send_response(202); self.end_headers(); return
        if m == "initialize":
            res, hdr = {"protocolVersion": "2025-03-26", "capabilities": {}}, {"Mcp-Session-Id": "s1"}
        elif m == "tools/list":
            res, hdr = {"tools": TOOLS}, {}
        else:
            name, a = d["params"]["name"], d["params"]["arguments"]
            CALLS.append((name, a))
            assert a.get("user_google_email") == "yo@example.com", a
            if name == "search_gmail_messages":
                txt = SEARCH
            elif name == "get_gmail_message_content":
                txt = "Message ID: m\nSubject: x\nFrom: y\n\n--- BODY ---\n" + ("Recuerda que el plazo termina mañana, entrega el impreso." if a["message_id"] == "m1" else "Contenido normal sin prisa.")
            elif name == "get_events":
                txt = ('Successfully retrieved 2 events from calendar \'primary\' for yo@example.com:\n'
                       f'- "Reunión TFG" (Starts: {SOON}, Ends: {SOON}) ID: ev1 | Link: https://calendar.google.com/event?eid=ev1\n'
                       '- "Cumpleaños" (Starts: 2026-10-22, Ends: 2026-10-23) ID: ev2 | Link: https://calendar.google.com/event?eid=ev2')
            else:
                txt = "Successfully created event 'X' for yo@example.com. Link: https://calendar.google.com/event?eid=new1"
            res, hdr = {"content": [{"type": "text", "text": txt}], "isError": False}, {}
        body = json.dumps({"jsonrpc": "2.0", "id": d.get("id"), "result": res})
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        for k, v in hdr.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body.encode())


def ok(cond, msg):
    print(("ok   " if cond else "FALLA"), msg)
    if not cond:
        sys.exit(1)


def main():
    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    from laura import jobs as J
    from laura import workspace as W
    from laura.config import CFG
    CFG["workspace"].update(url=f"http://127.0.0.1:{srv.server_port}/mcp", email="yo@example.com", timeout=5)
    CFG["background"]["vault"] = tempfile.mkdtemp()
    sp = tempfile.mkdtemp()

    # -- consulta combinada
    ok(W.combinar("de Marta").endswith("de Marta") and "category:primary" in W.combinar(""), "filtro base + consulta de Alberto")

    # -- tools directas
    from laura.tools import run_tool
    r = run_tool("correo", {}, {})
    ok(r["ok"] and len(r["correos"]) == 3 and r["decir"].startswith("Tienes 3 correos"), f"correo directo: {r['decir']}")
    q = [a for n, a in CALLS if n == "search_gmail_messages"][0]["query"]
    ok("is:unread" in q and "-category:promotions" in q, "query enviada con filtro y no leídos")
    r = run_tool("agenda", {"cuando": "hoy"}, {})
    ok(r["ok"] and "Reunión TFG" in r["decir"] and len(r["eventos"]) == 2, f"agenda directa: {r['decir']}")

    # -- crear evento: confirmación obligatoria
    answers = {"v": True}
    jm = J.JobManager(lambda t, **k: None)
    jm.on_confirm = lambda m: jm.confirm(m["id"], answers["v"])
    J.set_manager(jm)
    CALLS.clear()
    answers["v"] = False
    r = run_tool("crear_evento", {"titulo": "Dentista", "inicio": "2026-10-22T10:00", "duracion_min": 30}, {})
    ok(r["ok"], "crear_evento lanza trabajo en confirm")
    jm.wait_all(20)
    time.sleep(0.5)
    ok(not [c for c in CALLS if c[0] == "create_event"], "respondiendo NO no se crea nada")
    answers["v"] = True
    run_tool("crear_evento", {"titulo": "Dentista", "inicio": "2026-10-22T10:00", "duracion_min": 30}, {})
    jm.wait_all(20)
    time.sleep(0.5)
    cr = [a for n, a in CALLS if n == "create_event"]
    ok(len(cr) == 1 and cr[0]["summary"] == "Dentista" and cr[0]["end_time"].startswith("2026-10-22T10:30"), f"con SÍ se crea: {cr[0] if cr else None}")
    ultimo = J.list_jobs(1)[0]
    ok(ultimo["estado"] == "done" and ultimo["fuentes"], f"trabajo done con enlace: {ultimo['resumen']}")

    # -- redactar correo: agy simulado + Aurora simulada; no envía sin sí
    fake = Path(sp) / "fakeagy"
    fake.write_text('#!/bin/sh\necho \'{"para":"marta@x.com","asunto":"Llego tarde","cuerpo":"Hola Marta, llego tarde. Alberto"}\'\n')
    fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
    CFG["escalation"]["agy_bin"] = str(fake)
    from laura import aurora
    enviados = []
    aurora.run = lambda p, cancel, on_confirm, on_run=None, session_key=None: (enviados.append(p), {"ok": True, "texto": "Enviado"})[1]
    seen = {}
    jm.on_confirm = lambda m: (seen.update(m), jm.confirm(m["id"], answers["v"]))
    answers["v"] = False
    run_tool("redactar_correo", {"para": "Marta", "idea": "que llego tarde"}, {})
    jm.wait_all(30); time.sleep(0.5)
    ok(not enviados and "Hola Marta" in seen.get("pregunta", "") and seen.get("pregunta_voz") == "Te lo he escrito, ¿lo envío?",
       "redactar: texto exacto en la tarjeta, voz corta y NO => no se envía")
    answers["v"] = True
    run_tool("redactar_correo", {"para": "Marta", "idea": "que llego tarde"}, {})
    jm.wait_all(30); time.sleep(0.5)
    ok(len(enviados) == 1 and "YA lo ha confirmado" in enviados[0] and "Hola Marta, llego tarde" in enviados[0], "SÍ => Aurora recibe el correo exacto")

    # -- vigía: dedupe, prioridades, eventos
    from laura import vigia
    avisos = []

    class FakeJobs:
        def post_aviso(self, titulo, resumen, prioridad="normal", fuentes=None, cuerpo="", speak=True):
            avisos.append((titulo, prioridad, resumen))

    v = vigia.Vigia(FakeJobs(), {})
    n1 = v.check()
    prio = {t: p for t, p, _ in avisos}
    ok(prio.get("Correo de Secretaría") == "alta", "universidad/plazo => alta")
    ok(prio.get("Correo de Amazon") == "baja", "Notificaciones => baja")
    ok(prio.get("Correo de Marta") == "normal", "bandeja principal => normal")
    ok(prio.get("Evento: Reunión TFG") == "alta", "evento próximo => alta (todo el día ignorado)")
    n2 = v.check()
    ok(n1 >= 4 and n2 == 0 or n2 == 0, f"segunda revisión sin repetir ({n1} -> {n2})")
    ok(not any("Cumpleaños" in t for t, _, _ in avisos), "evento de todo el día ignorado")

    # -- respaldo a Aurora con el servidor caído
    srv.shutdown()
    W.reset()
    CFG["workspace"]["url"] = "http://127.0.0.1:1/mcp"
    r = run_tool("correo", {}, {})
    ok(r.get("via") == "aurora", "servidor caído => respaldo a Aurora en correo")
    r = run_tool("agenda", {"cuando": "mañana"}, {})
    ok(r.get("via") == "aurora", "servidor caído => respaldo a Aurora en agenda")
    print("TODO OK")


if __name__ == "__main__":
    main()
