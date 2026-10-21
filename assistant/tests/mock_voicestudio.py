"""Servidor MCP (Streamable HTTP) mínimo que imita VoiceStudio, para probar el motor `voicestudio`.

    python tests/mock_voicestudio.py          # prueba autónoma (arranca el mock y comprueba el motor)
"""
import base64
import io
import json
import sys
import threading
import wave
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def tone() -> bytes:
    b = io.BytesIO()
    with wave.open(b, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes(b"\x00\x10" * 8000)
    return b.getvalue()


def make_handler(sse: bool, log: list):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *a): pass

        def _reply(self, obj, headers=None):
            body = json.dumps(obj)
            if sse:
                body, ct = f"event: message\ndata: {body}\n\n", "text/event-stream"
            else:
                ct = "application/json"
            self.send_response(200)
            self.send_header("Content-Type", ct)
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body.encode())

        def do_POST(self):
            d = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            log.append((d.get("method"), self.headers.get("Mcp-Session-Id"), d.get("params")))
            m = d.get("method")
            if m == "initialize":
                self._reply({"jsonrpc": "2.0", "id": d["id"], "result": {"protocolVersion": "2025-03-26", "capabilities": {}, "serverInfo": {"name": "mock"}}}, {"Mcp-Session-Id": "sess-1"})
            elif m == "notifications/initialized":
                self.send_response(202); self.end_headers()
            elif m == "tools/call":
                inner = json.dumps({"wav_base64": base64.b64encode(tone()).decode(), "duration": 0.5})
                self._reply({"jsonrpc": "2.0", "id": d["id"], "result": {"content": [{"type": "text", "text": inner}], "isError": False}})
            else:
                self.send_response(400); self.end_headers()
    return H


def run() -> None:
    from laura.config import CFG
    from laura.engines.voicestudio import VoiceStudio
    from laura.engines import EngineUnavailable
    for sse in (False, True):
        log: list = []
        srv = HTTPServer(("127.0.0.1", 0), make_handler(sse, log))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        eng = VoiceStudio({"url": f"http://127.0.0.1:{srv.server_port}/mcp/", "profile_id": "voz-123", "timeout": 5})
        eng.synth("hola Alberto", "/tmp/vs_test.wav")
        eng.synth("otra frase", "/tmp/vs_test.wav")
        with wave.open("/tmp/vs_test.wav") as w:
            assert w.getnframes() == 8000
        metodos = [m for m, _, _ in log]
        assert metodos == ["initialize", "notifications/initialized", "tools/call", "tools/call"], metodos
        assert log[2][1] == "sess-1"  # reutiliza la sesión
        args = log[2][2]["arguments"]
        assert args == {"text": "hola Alberto", "profile_id": "voz-123", "language": "Spanish"}, args
        print(f"ok ({'SSE' if sse else 'JSON'}): {metodos}, args={args}")
        srv.shutdown()
    # servidor caído -> EngineUnavailable
    try:
        VoiceStudio({"url": "http://127.0.0.1:1/mcp/", "profile_id": "x", "timeout": 2}).synth("hola", "/tmp/vs_test.wav")
        raise SystemExit("debería haber fallado")
    except EngineUnavailable as e:
        print("caído ->", str(e)[:70])
    # cadena con respaldo: voicestudio caído -> piper
    CFG["tts"]["engine"] = "voicestudio"; CFG["tts"]["fallbacks"] = ["piper"]; CFG["tts"]["effect"] = "dry"
    CFG["tts"]["voicestudio"] = {"url": "http://127.0.0.1:1/mcp/", "profile_id": "x", "timeout": 2}
    from laura import tts
    w = tts._synth_wav("prueba de respaldo", "vsfb")
    print("respaldo ok ->", w, "| cadena:", tts.chain())


if __name__ == "__main__":
    run()
