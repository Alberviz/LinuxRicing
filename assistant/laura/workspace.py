"""Cliente directo del MCP de Google Workspace (taylorwilsdon/google_workspace_mcp, `workspace-mcp`).

Habla MCP Streamable HTTP con el servidor local (laura-workspace.service, 127.0.0.1:8765), sin LLM
de por medio. Los nombres de las herramientas se descubren con `tools/list` (no se codifican a ciegas):
  - buscar correos: `search_gmail_messages` (include_headers=True)
  - leer correo:    `get_gmail_message_content`
  - agenda:         `get_events`
  - crear evento:   `create_event`, o `manage_event` con action="create" en versiones nuevas
Las respuestas del servidor son texto «para LLM», que aquí se parsea a dicts.
Si el servidor no responde se lanza WorkspaceUnavailable y quien llama cae a Aurora."""
from __future__ import annotations

import json
import re
import threading
from datetime import datetime, timedelta

import requests

from .config import CFG, log
from .engines.voicestudio import _json_body

_PROTOCOL = "2025-03-26"

# «Olvídate del spam; bandeja principal y Notificaciones» (Alberto).
BASE_QUERY = ("in:inbox (category:primary OR category:updates) -category:promotions "
              "-category:social -category:forums -in:spam")


class WorkspaceUnavailable(RuntimeError):
    """El servidor no responde o falta una herramienta: usar el respaldo (Aurora)."""


class WorkspaceAuthRequired(WorkspaceUnavailable):
    """Faltan credenciales de Google: `url` es la dirección de autorización."""

    def __init__(self, url: str = "") -> None:
        super().__init__("Google necesita autorización" + (f": {url}" if url else ""))
        self.url = url


def _cfg() -> dict:
    return CFG.get("workspace", {})


def enabled() -> bool:
    return bool(_cfg().get("enabled", True))


def combinar(consulta: str = "") -> str:
    """Consulta de Alberto + filtro base."""
    c = (consulta or "").strip()
    return f"{BASE_QUERY} {c}" if c else BASE_QUERY


class Client:
    def __init__(self, url: str | None = None, timeout: float | None = None, email: str | None = None) -> None:
        c = _cfg()
        self.url = url or c.get("url", "http://127.0.0.1:8765/mcp")
        self.timeout = float(timeout or c.get("timeout", 20))
        self.email = email if email is not None else c.get("email", "")
        self._session: str | None = None
        self._id = 0
        self._tools: dict[str, dict] | None = None
        self._lock = threading.Lock()

    # -- transporte
    def _headers(self) -> dict:
        h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
             "MCP-Protocol-Version": _PROTOCOL}
        if self._session:
            h["Mcp-Session-Id"] = self._session
        return h

    def _post(self, payload: dict, reply: bool = True) -> dict:
        try:
            r = requests.post(self.url, json=payload, headers=self._headers(), timeout=self.timeout)
        except requests.RequestException as e:
            self._session = None
            raise WorkspaceUnavailable(f"Workspace no responde en {self.url}: {type(e).__name__}") from e
        if r.status_code == 404:
            self._session = None
        if r.status_code >= 400:
            raise WorkspaceUnavailable(f"Workspace HTTP {r.status_code}: {r.text[:120]}")
        self._last = r
        return _json_body(r) if reply else {}

    def _init(self) -> None:
        self._id += 1
        self._session = None
        self._post({"jsonrpc": "2.0", "id": self._id, "method": "initialize",
                    "params": {"protocolVersion": _PROTOCOL, "capabilities": {},
                               "clientInfo": {"name": "laura", "version": "2"}}})
        self._session = self._last.headers.get("Mcp-Session-Id") or self._last.headers.get("mcp-session-id")
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"}, reply=False)
        self._id += 1
        d = self._post({"jsonrpc": "2.0", "id": self._id, "method": "tools/list"})
        self._tools = {t["name"]: t for t in (d.get("result") or {}).get("tools", [])}
        log(f"workspace: {len(self._tools)} herramientas MCP")

    def tools(self) -> dict[str, dict]:
        with self._lock:
            if self._tools is None or self._session is None:
                self._init()
            return self._tools or {}

    def tool_name(self, *candidatos: str) -> str:
        t = self.tools()
        for c in candidatos:
            if c in t:
                return c
        raise WorkspaceUnavailable(f"el servidor no tiene ninguna de {candidatos} (¿--permissions?)")

    def call(self, name: str, args: dict) -> str:
        schema = (self.tools().get(name) or {}).get("inputSchema", {})
        if "user_google_email" in (schema.get("properties") or {}) and "user_google_email" not in args:
            if not self.email:
                raise WorkspaceUnavailable("falta [workspace] email (user_google_email)")
            args = {**args, "user_google_email": self.email}
        with self._lock:
            self._id += 1
            d = self._post({"jsonrpc": "2.0", "id": self._id, "method": "tools/call",
                            "params": {"name": name, "arguments": args}})
        if "error" in d:
            raise WorkspaceUnavailable(f"{name}: {d['error'].get('message', d['error'])}")
        res = d.get("result") or {}
        txt = "\n".join(c.get("text", "") for c in res.get("content") or [] if c.get("type") == "text")
        if txt.lstrip().startswith("**ACTION REQUIRED"):
            m = re.search(r"https?://\S+", txt)
            raise WorkspaceAuthRequired(m.group(0).rstrip(").,*") if m else "")
        if res.get("isError"):
            raise WorkspaceUnavailable(f"{name}: {txt[:200] or 'error'}")
        return txt


_CLIENT: Client | None = None


def client() -> Client:
    global _CLIENT
    if _CLIENT is None:
        _CLIENT = Client()
    return _CLIENT


def reset() -> None:
    global _CLIENT
    _CLIENT = None


# -------------------------------------------------------------------- parseo
def _parse_search(txt: str) -> list[dict]:
    out: list[dict] = []
    cur: dict | None = None
    for line in txt.splitlines():
        s = line.strip()
        m = re.match(r"\d+\.\s*Message ID:\s*(\S+)", s)
        if m:
            cur = {"id": m.group(1), "asunto": "", "de": "", "fecha": "", "etiquetas": "", "url": ""}
            out.append(cur)
        elif cur is not None:
            for key, campo in (("Subject:", "asunto"), ("From:", "de"), ("Date:", "fecha"),
                               ("Labels:", "etiquetas"), ("Web Link:", "url")):
                if s.startswith(key):
                    cur[campo] = s[len(key):].strip()
    return out


def buscar_correos(query: str, n: int = 5) -> list[dict]:
    """Correos que cumplen `query` (úsala con combinar()). -> [{id, asunto, de, fecha, etiquetas, url}]"""
    c = client()
    txt = c.call(c.tool_name("search_gmail_messages"),
                 {"query": query, "page_size": n, "include_headers": True})
    return _parse_search(txt)[:n]


def leer_correo(msg_id: str, max_chars: int = 600) -> str:
    """Cuerpo en texto (recortado) del mensaje."""
    c = client()
    txt = c.call(c.tool_name("get_gmail_message_content"), {"message_id": msg_id})
    cuerpo = txt.split("--- BODY ---", 1)[1] if "--- BODY ---" in txt else txt
    cuerpo = re.sub(r"\s+", " ", cuerpo.split("--- ATTACHMENTS ---")[0]).strip()
    return cuerpo[:max_chars]


_EV = re.compile(r'^-\s*"(?P<t>.*)"\s*\(Starts:\s*(?P<s>.*?),\s*Ends:\s*(?P<e>.*?)\)(?P<resto>.*)$')


def _parse_events(txt: str) -> list[dict]:
    out = []
    for line in txt.splitlines():
        m = _EV.match(line.strip())
        if not m:
            continue
        resto = m.group("resto")
        id_ = re.search(r"ID:\s*(\S+)", resto)
        link = re.search(r"Link:\s*(\S+)", resto)
        out.append({"titulo": m.group("t"), "inicio": re.sub(r"\s*\[.*$", "", m.group("s")),
                    "fin": re.sub(r"\s*\[.*$", "", m.group("e")),
                    "id": id_.group(1) if id_ else "", "url": link.group(1) if link and link.group(1) != "No" else ""})
    return out


def eventos(desde: datetime, hasta: datetime, n: int = 15) -> list[dict]:
    """Eventos entre dos instantes (hora local)."""
    c = client()
    f = lambda d: d.astimezone().isoformat(timespec="seconds")  # noqa: E731
    txt = c.call(c.tool_name("get_events"), {"time_min": f(desde), "time_max": f(hasta), "max_results": n})
    return _parse_events(txt)


def crear_evento(titulo: str, inicio: datetime, fin: datetime, descripcion: str = "") -> dict:
    """Crea un evento en el calendario principal. -> {ok, id, url, texto}"""
    c = client()
    name = c.tool_name("create_event", "manage_event")
    f = lambda d: d.astimezone().isoformat(timespec="seconds")  # noqa: E731
    args = {"summary": titulo, "start_time": f(inicio), "end_time": f(fin)}
    if descripcion:
        args["description"] = descripcion
    if name == "manage_event":
        args["action"] = "create"
    txt = c.call(name, args)
    id_ = re.search(r"ID:\s*([^\s,]+)", txt)
    link = re.search(r"Link:\s*(\S+)", txt)
    return {"ok": True, "id": id_.group(1) if id_ else "", "url": link.group(1) if link else "", "texto": txt[:200]}


def rango(cuando: str, ahora: datetime | None = None) -> tuple[datetime, datetime]:
    ahora = (ahora or datetime.now()).astimezone()
    dia = ahora.replace(hour=0, minute=0, second=0, microsecond=0)
    c = (cuando or "hoy").lower()
    if c in ("mañana", "manana"):
        return dia + timedelta(days=1), dia + timedelta(days=2)
    if c == "semana":
        return ahora, dia + timedelta(days=7)
    if c in ("próximo", "proximo"):
        return ahora, ahora + timedelta(days=30)
    return ahora, dia + timedelta(days=1)
