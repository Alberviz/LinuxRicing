"""VoiceStudio por MCP (Streamable HTTP) en http://127.0.0.1:3900/mcp/.

Voz propia (clonada o diseñada) servida por VoiceStudio. Protocolo (docs/mcp.md de VoiceStudio):
JSON-RPC 2.0 por POST → `initialize`, `notifications/initialized` y `tools/call` de
`generate_speech` {text, profile_id, language}. La respuesta trae `wav_base64`. Solo `requests`.

Config en `[tts.voicestudio]`: url, profile_id, timeout, language, client_id.
Si el servidor no responde se lanza EngineUnavailable y laura.tts aparca el motor y pasa
al siguiente de la cadena (kokoro).
"""
from __future__ import annotations

import base64
import json

import requests

from . import Engine, EngineUnavailable, engine

_PROTOCOL = "2025-03-26"


def _json_body(r: requests.Response) -> dict:
    """La respuesta de Streamable HTTP puede ser JSON o un stream SSE con el mensaje en `data:`."""
    ctype = r.headers.get("Content-Type", "")
    if "charset" not in ctype.lower():
        r.encoding = "utf-8"  # requests asume ISO-8859-1 en text/*; el MCP siempre manda UTF-8
    if "text/event-stream" in ctype:
        msg = None
        for line in r.text.splitlines():
            if line.startswith("data:"):
                try:
                    d = json.loads(line[5:].strip())
                except ValueError:
                    continue
                if isinstance(d, dict) and ("result" in d or "error" in d):
                    msg = d
        if msg is None:
            raise EngineUnavailable("VoiceStudio: respuesta SSE sin resultado")
        return msg
    return r.json() if r.content else {}


def _find_wav(result: dict) -> str | None:
    """Busca `wav_base64` en structuredContent, en el texto JSON de content[] o en recursos embebidos."""
    sc = result.get("structuredContent")
    if isinstance(sc, dict):
        if sc.get("wav_base64"):
            return sc["wav_base64"]
        if isinstance(sc.get("result"), dict) and sc["result"].get("wav_base64"):
            return sc["result"]["wav_base64"]
    for item in result.get("content") or []:
        if item.get("type") == "text":
            try:
                d = json.loads(item.get("text", ""))
            except ValueError:
                continue
            if isinstance(d, dict) and d.get("wav_base64"):
                return d["wav_base64"]
        elif item.get("type") == "audio" and item.get("data"):
            return item["data"]
        elif item.get("type") == "resource":
            res = item.get("resource") or {}
            if res.get("blob"):
                return res["blob"]
            try:
                d = json.loads(res.get("text", ""))
                if isinstance(d, dict) and d.get("wav_base64"):
                    return d["wav_base64"]
            except ValueError:
                pass
    return None


@engine("voicestudio")
class VoiceStudio(Engine):
    def __init__(self, cfg: dict) -> None:
        super().__init__(cfg)
        self.url = cfg.get("url", "http://127.0.0.1:3900/mcp/")
        self.timeout = float(cfg.get("timeout", 60))
        self._session: str | None = None
        self._id = 0

    def _headers(self) -> dict:
        h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
             "MCP-Protocol-Version": _PROTOCOL}
        if self.cfg.get("client_id"):
            h["X-OmniVoice-Client-Id"] = self.cfg["client_id"]
        if self._session:
            h["Mcp-Session-Id"] = self._session
        return h

    def _post(self, payload: dict, expect_reply: bool = True) -> dict:
        try:
            r = requests.post(self.url, json=payload, headers=self._headers(), timeout=self.timeout)
        except requests.RequestException as e:
            self._session = None
            raise EngineUnavailable(f"VoiceStudio no responde en {self.url}: {e}") from e
        if r.status_code == 404 and self._session:  # sesión caducada: reinicializar la próxima vez
            self._session = None
        if r.status_code >= 400:
            raise EngineUnavailable(f"VoiceStudio HTTP {r.status_code}: {r.text[:120]}")
        if not expect_reply:
            return {}
        return _json_body(r)

    def _initialize(self) -> None:
        self._id += 1
        try:
            r = requests.post(self.url, headers=self._headers(), timeout=self.timeout, json={
                "jsonrpc": "2.0", "id": self._id, "method": "initialize",
                "params": {"protocolVersion": _PROTOCOL, "capabilities": {},
                           "clientInfo": {"name": "laura", "version": "2"}}})
        except requests.RequestException as e:
            raise EngineUnavailable(f"VoiceStudio no responde en {self.url}: {e}") from e
        if r.status_code >= 400:
            raise EngineUnavailable(f"VoiceStudio initialize HTTP {r.status_code}")
        self._session = r.headers.get("Mcp-Session-Id") or r.headers.get("mcp-session-id")
        _json_body(r)
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"}, expect_reply=False)

    def warmup(self) -> None:
        self._initialize()

    def synth(self, text: str, out_wav: str) -> None:
        if not self.cfg.get("profile_id"):
            raise EngineUnavailable("[tts.voicestudio] profile_id vacío (crea una voz con design_voice o clone_voice)")
        if self._session is None:
            self._initialize()
        self._id += 1
        args = {"text": text, "profile_id": self.cfg["profile_id"],
                "language": self.cfg.get("language", "Spanish")}
        d = self._post({"jsonrpc": "2.0", "id": self._id, "method": "tools/call",
                        "params": {"name": "generate_speech", "arguments": args}})
        if "error" in d:
            raise EngineUnavailable(f"VoiceStudio: {d['error'].get('message', d['error'])}")
        result = d.get("result") or {}
        if result.get("isError"):
            msg = " ".join(c.get("text", "") for c in result.get("content") or [])[:160]
            raise EngineUnavailable(f"VoiceStudio: {msg or 'error en generate_speech'}")
        b64 = _find_wav(result)
        if not b64:
            raise EngineUnavailable("VoiceStudio: la respuesta no trae wav_base64")
        with open(out_wav, "wb") as f:
            f.write(base64.b64decode(b64))
