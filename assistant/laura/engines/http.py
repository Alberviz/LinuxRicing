"""Motor HTTP genérico: POST del texto a una URL que devuelve un WAV.

Pensado para apuntar a backends de voz propia servidos aparte (VoiceStudio en
localhost:3900, OmniVoice, PocketTTS…). Config en `[tts.http]`:

    url = "http://localhost:3900/tts"
    format = "json"            # json | form  (cómo se manda el cuerpo)
    text_field = "text"        # nombre del campo con el texto
    ref_audio = ""             # audio de referencia para clonar la voz (ruta a un .wav)
    ref_audio_mode = "path"    # path: se manda la ruta | base64: se manda el contenido
    ref_text = ""              # transcripción del audio de referencia
    timeout = 60
    extra = { voice = "laura" }  # campos fijos adicionales

La respuesta debe ser un WAV (cuerpo binario) o un JSON {"audio_base64": "..."}.
"""
from __future__ import annotations

import base64
import json
import urllib.parse
import urllib.request
from pathlib import Path

from . import Engine, EngineUnavailable, engine


@engine("http")
class Http(Engine):
    def synth(self, text: str, out_wav: str) -> None:
        url = self.cfg.get("url")
        if not url:
            raise EngineUnavailable("[tts.http] url vacía")
        payload = {self.cfg.get("text_field", "text"): text, **self.cfg.get("extra", {})}
        ref = self.cfg.get("ref_audio", "")
        if ref:
            p = Path(ref).expanduser()
            if self.cfg.get("ref_audio_mode", "path") == "base64":
                payload["ref_audio"] = base64.b64encode(p.read_bytes()).decode()
            else:
                payload["ref_audio"] = str(p)
            if self.cfg.get("ref_text"):
                payload["ref_text"] = self.cfg["ref_text"]
        if self.cfg.get("format", "json") == "form":
            data = urllib.parse.urlencode(payload).encode()
            ctype = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(payload).encode()
            ctype = "application/json"
        req = urllib.request.Request(url, data=data, headers={"Content-Type": ctype})
        try:
            with urllib.request.urlopen(req, timeout=float(self.cfg.get("timeout", 60))) as r:
                body = r.read()
                is_json = "json" in (r.headers.get("Content-Type") or "")
        except OSError as e:
            raise EngineUnavailable(f"{url}: {e}") from e
        if is_json:
            body = base64.b64decode(json.loads(body)["audio_base64"])
        Path(out_wav).write_bytes(body)
