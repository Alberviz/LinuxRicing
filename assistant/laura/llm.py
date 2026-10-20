"""LLM local (Ollama): historial, streaming por frases, bucle de herramientas y modo calidad."""
from __future__ import annotations

import json
import re
import threading
import urllib.request

import tools as tools_mod

from .config import CFG, log

# ----------------------------------------------------------------------- estado
_messages = [{"role": "system", "content": CFG["llm"]["system_prompt"].strip()}]

# "Modo calidad": usa un modelo mayor (`llm.model_quality`, p. ej. qwen3:8b) para
# respuestas más elaboradas / código. Vacío en config = desactivado. Se alterna
# por voz («modo calidad» / «modo rápido»).
_quality = [False]
_MODE_ON = ("modo calidad", "modo potente", "modo experto", "mas potente", "más potente")
_MODE_OFF = ("modo rapido", "modo rápido", "modo normal", "modo ligero")


def _mode_switch(text: str) -> bool | None:
    """True = pasar a modo calidad, False = volver al rápido, None = no aplica."""
    if not CFG["llm"].get("model_quality"):
        return None
    t = text.lower()
    if any(k in t for k in _MODE_ON):
        return True
    if any(k in t for k in _MODE_OFF):
        return False
    return None


def _model_now() -> str:
    if _quality[0] and CFG["llm"].get("model_quality"):
        return CFG["llm"]["model_quality"]
    return CFG["llm"]["model"]



def _ollama_body(stream: bool) -> bytes:
    return json.dumps({
        "model": _model_now(),
        "messages": _messages,
        "tools": tools_mod.TOOLS,
        "stream": stream,
        "options": {"num_ctx": CFG["llm"].get("num_ctx", 4096)},
    }).encode()


def ollama_chat(messages: list[dict]) -> dict:
    req = urllib.request.Request(CFG["llm"]["url"], data=_ollama_body(False),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=CFG["llm"].get("timeout", 45)) as resp:
        return json.loads(resp.read())


# Fin de frase: puntuación terminal seguida de un espacio (para no cortar en el
# punto de "3.5"), o un salto de línea. Trocea la respuesta según se genera para
# mandar cada frase ya a la voz sin esperar al resto.
_SENT_END = re.compile(r"[.!?…]+[\"'’”)\]]*(?=\s)|\n")


def _drain_sentences(buf: str) -> tuple[list[str], str]:
    """Extrae de `buf` las frases ya completas; devuelve (frases, resto)."""
    out: list[str] = []
    while (m := _SENT_END.search(buf)):
        cut = m.end()
        frag = buf[:cut].strip()
        if frag:
            out.append(frag)
        buf = buf[cut:].lstrip()
    return out, buf


def _ollama_stream(cancel: threading.Event | None):
    """Itera la respuesta de Ollama token a token (líneas JSON)."""
    req = urllib.request.Request(CFG["llm"]["url"], data=_ollama_body(True),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=CFG["llm"].get("timeout", 45)) as resp:
        for raw in resp:
            if cancel is not None and cancel.is_set():
                return
            raw = raw.strip()
            if raw:
                yield json.loads(raw)


def _stream_round(on_sentence, cancel: threading.Event | None) -> tuple[str, list]:
    """Una ronda del LLM en streaming. Devuelve (texto completo, tool_calls).
    Mientras no aparezcan tool_calls, cada frase terminada se manda a `on_sentence`
    (para que la voz empiece ya). Si es una ronda de herramientas, no habla."""
    parts: list[str] = []
    calls: list = []
    buf = ""
    for chunk in _ollama_stream(cancel):
        m = chunk.get("message") or {}
        if m.get("tool_calls"):
            calls += m["tool_calls"]
        piece = m.get("content") or ""
        if piece:
            parts.append(piece)
            if on_sentence is not None and not calls:
                buf += piece
                sents, buf = _drain_sentences(buf)
                for s in sents:
                    on_sentence(s)
        if chunk.get("done"):
            break
    if on_sentence is not None and not calls and buf.strip():
        on_sentence(buf.strip())
    return "".join(parts), calls


def _trim_history() -> None:
    """Acota el historial: aunque el contexto de Ollama sea holgado
    (`llm.num_ctx` en config.toml), si `_messages` crece sin límite las
    respuestas se vuelven lentísimas y el modelo se despista. `history_msgs`
    manda sobre el contexto: es cuántos turnos de conversación recuerda Laura."""
    keep = CFG["llm"].get("history_msgs", 12)
    if len(_messages) <= keep + 1:
        return
    tail = _messages[-keep:]
    # No arrancar el tail con respuestas de herramienta huérfanas ni con un
    # assistant que referencia tool_calls ya recortados.
    while tail and (tail[0].get("role") == "tool"
                    or (tail[0].get("role") == "assistant" and tail[0].get("tool_calls"))):
        tail.pop(0)
    _messages[:] = [_messages[0], *tail]


def converse(user_text: str, on_sentence=None,
             cancel: threading.Event | None = None
             ) -> tuple[str, list[dict], dict | None]:
    """Devuelve (respuesta, acciones, escalada) donde acciones = [{icon, text},
    ...] y `escalada` es None salvo que el LLM haya llamado a la herramienta
    `escalar_a_gemini` (Modo B): entonces es {"peticion":..., "motivo":...} y
    `cycle()` se encarga de confirmar con Alberto antes de lanzar nada — no se
    sigue el bucle de tools con normalidad en esa ronda.

    Si `on_sentence` no es None, la respuesta final se genera en streaming y
    cada frase terminada se le pasa según se produce (voz por frases)."""
    _trim_history()
    _messages.append({"role": "user", "content": user_text})
    actions: list[dict] = []
    for _ in range(CFG["llm"]["max_tool_rounds"]):
        if on_sentence is not None:
            content, calls = _stream_round(on_sentence, cancel)
            _messages.append({"role": "assistant", "content": content,
                              **({"tool_calls": calls} if calls else {})})
        else:
            msg = ollama_chat(_messages)["message"]
            _messages.append(msg)
            content, calls = msg.get("content") or "", msg.get("tool_calls") or []
        if not calls:
            return content.strip(), actions, None
        for call in calls:
            fn = call["function"]
            args = fn.get("arguments") or {}
            if isinstance(args, str):
                args = json.loads(args or "{}")
            result = tools_mod.run_tool(fn["name"], args, CFG.get("apps", {}))
            log(f"tool {fn['name']}({args}) -> {result}")
            _messages.append({"role": "tool", "name": fn["name"],
                              "content": json.dumps(result, ensure_ascii=False)})
            if fn["name"] == "escalar_a_gemini":
                return "", actions, {
                    "peticion": args.get("peticion") or user_text,
                    "motivo": args.get("motivo", ""),
                }
            if result.get("ok"):
                actions.append(tools_mod.accion_overlay(fn["name"], result))
    return (_messages[-1].get("content") or "Hecho.").strip(), actions, None
