# Laura Holo — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Laura enseña archivos en paneles holográficos (lista numerada + visores) que se manejan por voz y ratón, y «envía esa al móvil» los manda por warp.

**Architecture:** El daemon de Laura es dueño de una `Escena` (Python) que numera archivos, guarda los paneles abiertos y emite eventos `{"type":"holo",…}` por el bus que ya existe; Quickshell los pinta con un módulo nuevo `modules/holo/` y devuelve lo que hace el ratón por el socket de control. El LLM recibe una línea con «lo que hay en pantalla» en el system prompt.

**Tech Stack:** Python 3 (daemon `assistant/laura`, pytest), Quickshell / QML (Qt 6.12, QtMultimedia), `pdftoppm`, `ffmpegthumbnailer`, Pillow, CLI `warp`.

**Spec:** `docs/superpowers/specs/2026-11-09-laura-holo-design.md`

## Global Constraints

- Rama `feat/laura-holo`. **Los agentes NO hacen commit**: el orquestador revisa y commitea cada tarea. Otros agentes (Gemini en `vault/`) trabajan en el mismo repo: no toques archivos fuera de los de tu tarea y nunca hagas `git add -A`, `git stash`, `git checkout -- .` ni `git reset`.
- Todo el texto visible y los comentarios en **español**, con tildes y eñes correctas.
- Python: `from __future__ import annotations`, sin dependencias nuevas (Pillow ya está; si falta, se degrada sin tamaño).
- Tests: `cd assistant && python3 -m pytest -q tests` debe seguir en verde (hoy pasan 64).
- QML: colores **solo** de `Colours.palette.m3*` (Material You), tamaños de `Tokens`. Prohibido `FrameAnimation { running: true }` incondicional y `shadowBlur`/`layer.effect` de sombra animados. Toda animación con `running:` condicionado a que haya escena visible.
- Tras tocar QML: sincronizar a `~/.config/quickshell/caelestia/` y reiniciar con `caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d`, y comprobar `INFO: Configuration Loaded` sin errores. Nunca fiarse del hot-reload.
- Formato del evento (contrato Python ⇄ QML, no se cambia sin tocar los dos lados):
  `{"type":"holo","op":"snapshot"|"list"|"open"|"close"|"select"|"sent"|"page"|"clear","items":[Item…],"paneles":[Panel…],"seleccionado":int|null,"panel":Panel|null,"ids":[str…]|null}`
  `Item = {"n":int,"ruta":str,"nombre":str,"tipo":"imagen"|"pdf"|"texto"|"video"|"audio"|"otro","tamano":int,"mtime":float,"enviado":bool}`
  `Panel = {"id":str,"kind":"lista"|"visor","titulo":str,"item_n":int|null,"payload":dict}` — id `"lista"` para la lista, `"v<n>"` para el visor del item n.
  Todos los eventos llevan siempre `items`, `paneles` y `seleccionado` completos (estado entero, el QML no necesita reconstruir nada); `panel`/`ids` indican qué cambió para animar.

---

## Mapa de archivos

| Archivo | Responsabilidad |
|---|---|
| `assistant/laura/holo_preview.py` (nuevo) | `tipo_de(ruta)`, `preparar(ruta, tipo)` → payload del visor, `pagina_pdf(ruta, p)` |
| `assistant/laura/holo.py` (nuevo) | `Escena` (estado, eventos, contexto, comandos de control) + `escena()` singleton |
| `assistant/laura/tools/holo.py` (nuevo) | tools `mostrar_archivos`, `abrir`, `cerrar_holo` |
| `assistant/laura/tools/warp.py` | parámetro `numero`; listar/buscar también rellenan la escena; marcar enviado |
| `assistant/laura/tools/__init__.py` | registrar `holo` |
| `assistant/laura/events.py` | ganchos `on_connect` (snapshot de la escena a lectores nuevos) |
| `assistant/laura/llm.py` | `refresh_system` añade `escena().contexto()` |
| `assistant/laura/daemon.py` | `holo-*` en `control()`; `caducar()` en el janitor |
| `assistant/config.toml` | una línea en `system_prompt` |
| `assistant/eval/frases.toml` | frases nuevas del grupo `holo` |
| `configs/quickshell/caelestia/modules/assistant/HoloState.qml` (nuevo) | singleton: modelo QML de la escena + comandos al daemon |
| `configs/quickshell/caelestia/modules/assistant/Laura.qml` | `case "holo"` → `HoloState.handle(ev)`; `ctrl(cmd)` público |
| `configs/quickshell/caelestia/modules/holo/HoloOverlay.qml` (nuevo) | entrada: `Variants` por pantalla |
| `configs/quickshell/caelestia/modules/holo/HoloLayer.qml` (nuevo) | ventana overlay: velo, malla, paneles, hilos, Esc |
| `configs/quickshell/caelestia/modules/holo/HoloPlacer.js` (nuevo) | colocación semi-aleatoria sin solapes |
| `configs/quickshell/caelestia/modules/holo/HoloPanel.qml` (nuevo) | chasis del holograma + animaciones |
| `configs/quickshell/caelestia/modules/holo/HoloList.qml`, `HoloImage.qml`, `HoloPdf.qml`, `HoloMedia.qml`, `HoloText.qml`, `HoloOther.qml` (nuevos) | contenido por tipo |
| `configs/quickshell/caelestia/modules/holo/HoloLinks.qml` (nuevo) | hilos de puntos fila → visor |
| `configs/quickshell/caelestia/modules/holo/assets/scan.png`, `dots.png` (nuevos) | texturas en tile (líneas de escaneo, malla de puntos) |
| `configs/quickshell/caelestia/shell.qml` | `import "modules/holo"` + `HoloOverlay {}` |
| `docs/LAURA-HOLO.md` (nuevo) | uso, comandos, IPC de prueba |

---

### Task 1: `holo_preview.py` — tipo y vista previa de un archivo

**Agente:** Gemini 3.8 Flash (medium)

**Files:**
- Create: `assistant/laura/holo_preview.py`
- Test: `assistant/tests/test_holo_preview.py`

**Interfaces:**
- Produces:
  - `tipo_de(ruta: str) -> str` ∈ `imagen|pdf|texto|video|audio|otro`
  - `preparar(ruta: str, tipo: str) -> dict` — siempre incluye `"tipo"`; ver tabla
  - `pagina_pdf(ruta: str, p: int) -> str | None` — ruta del PNG de la página `p` (1-based) o `None`
  - `CACHE: Path` = `$XDG_RUNTIME_DIR/laura-holo` (o `/tmp/laura-holo-<uid>`); `limpiar_cache() -> None`

Payloads de `preparar`:

| tipo | payload |
|---|---|
| imagen | `{"tipo":"imagen","src":ruta,"w":int,"h":int}` (w/h = 0 si Pillow no puede) |
| pdf | `{"tipo":"pdf","src":<png p1>,"pagina":1,"paginas":N}`; si `pdftoppm`/`pdfinfo` faltan o fallan → payload `otro` con `"aviso"` |
| video | `{"tipo":"video","src":ruta,"poster":<png o "">}` (poster con `ffmpegthumbnailer -i ruta -o png -s 640`) |
| audio | `{"tipo":"audio","src":ruta}` |
| texto | `{"tipo":"texto","texto":str,"formato":"markdown"|"mono","truncado":bool}` — máx. 200 líneas y 16 KiB, decodificado `utf-8` con `errors="replace"` |
| otro | `{"tipo":"otro","mime":str,"icono":str}` (+ `"aviso"` opcional) |

Extensiones: imagen `png jpg jpeg webp gif bmp avif`; pdf `pdf`; video `mp4 mkv webm mov avi m4v`; audio `mp3 ogg oga opus wav flac m4a`; texto `md txt py json toml sh fish qml js ts css html yaml yml cfg ini log csv conf rs c h cpp go java kt lua sql xml`. Sin extensión conocida: `file --brief --mime-type` → `image/*`→imagen, `text/*`→texto, `video/*`, `audio/*`, `application/pdf`. Archivos de más de 2 GB → `otro` con aviso «Demasiado grande para previsualizar». Ruta inexistente → `{"tipo":"otro","mime":"","icono":"error","aviso":"Ya no existe"}`.

Iconos (`otro`): Material Symbols — `folder_zip` para zip/tar/gz/7z/rar, `description` para doc/docx/odt, `table` para xls/xlsx/ods/csv, `download` para torrent, `draft` por defecto.

Nombre del PNG en caché: `CACHE / f"{sha1(ruta + str(mtime)).hexdigest()[:16]}-p{p}.png"`; si ya existe, no se regenera. `pdftoppm -r 110 -f p -l p -png -singlefile ruta <sin .png>`. `paginas` con `pdfinfo ruta` (línea `Pages:`). `limpiar_cache()` borra la carpeta si pasa de 200 MB (y se llama al arrancar el daemon en la Task 3).

- [ ] **Step 1: Write the failing tests**

```python
"""Vista previa de archivos para los hologramas de Laura (sin pdftoppm real)."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura import holo_preview as hp  # noqa: E402


@pytest.fixture(autouse=True)
def cache(tmp_path, monkeypatch):
    monkeypatch.setattr(hp, "CACHE", tmp_path / "cache")


@pytest.mark.parametrize("nombre,tipo", [
    ("a.PNG", "imagen"), ("b.jpeg", "imagen"), ("c.pdf", "pdf"), ("d.mp4", "video"),
    ("e.ogg", "audio"), ("f.md", "texto"), ("g.py", "texto"), ("h.torrent", "otro"),
])
def test_tipo_por_extension(tmp_path, nombre, tipo):
    p = tmp_path / nombre
    p.write_bytes(b"x")
    assert hp.tipo_de(str(p)) == tipo


def test_texto_truncado_y_formato(tmp_path):
    p = tmp_path / "notas.md"
    p.write_text("\n".join(f"línea {i}" for i in range(500)), encoding="utf-8")
    d = hp.preparar(str(p), "texto")
    assert d["tipo"] == "texto" and d["formato"] == "markdown" and d["truncado"]
    assert d["texto"].count("\n") <= 200
    q = tmp_path / "main.py"
    q.write_text("print('hola')\n")
    d = hp.preparar(str(q), "texto")
    assert d["formato"] == "mono" and not d["truncado"] and "hola" in d["texto"]


def test_inexistente(tmp_path):
    d = hp.preparar(str(tmp_path / "nada.png"), "imagen")
    assert d == {"tipo": "otro", "mime": "", "icono": "error", "aviso": "Ya no existe"}


def test_imagen_con_tamano(tmp_path):
    from PIL import Image
    p = tmp_path / "c.png"
    Image.new("RGB", (30, 20)).save(p)
    d = hp.preparar(str(p), "imagen")
    assert d == {"tipo": "imagen", "src": str(p), "w": 30, "h": 20}


def test_pdf_sin_poppler_es_otro(tmp_path, monkeypatch):
    p = tmp_path / "x.pdf"
    p.write_bytes(b"%PDF-1.4")
    monkeypatch.setattr(hp.shutil, "which", lambda _: None)
    d = hp.preparar(str(p), "pdf")
    assert d["tipo"] == "otro" and d.get("aviso")


def test_pdf_con_poppler_falso(tmp_path, monkeypatch):
    p = tmp_path / "x.pdf"
    p.write_bytes(b"%PDF-1.4")
    llamadas = []

    def run(cmd, **kw):
        llamadas.append(cmd)
        class R:
            returncode = 0
            stdout = "Title: x\nPages:          12\n"
        if cmd[0].endswith("pdftoppm"):
            Path(cmd[-1] + ".png").parent.mkdir(parents=True, exist_ok=True)
            Path(cmd[-1] + ".png").write_bytes(b"png")
        return R()
    monkeypatch.setattr(hp.shutil, "which", lambda b: f"/usr/bin/{b}")
    monkeypatch.setattr(hp.subprocess, "run", run)
    d = hp.preparar(str(p), "pdf")
    assert d["tipo"] == "pdf" and d["paginas"] == 12 and d["pagina"] == 1 and d["src"].endswith("-p1.png")
    assert hp.pagina_pdf(str(p), 3).endswith("-p3.png")
    n = len(llamadas)
    hp.pagina_pdf(str(p), 3)          # en caché: no vuelve a llamar a pdftoppm
    assert len(llamadas) == n
```

- [ ] **Step 2:** `cd assistant && python3 -m pytest -q tests/test_holo_preview.py` → FAIL (`No module named laura.holo_preview`).
- [ ] **Step 3:** Implementar `holo_preview.py` según la tabla. Usar `subprocess.run([...], capture_output=True, text=True, timeout=20)`; cualquier excepción (`OSError`, `TimeoutExpired`, `ValueError`) → payload `otro` con `aviso`, nunca propagar.
- [ ] **Step 4:** `python3 -m pytest -q tests/test_holo_preview.py` → PASS; `python3 -m pytest -q tests` → todo verde.

---

### Task 2: `holo.py` — la escena

**Agente:** Gemini 3.8 Flash (high)

**Files:**
- Create: `assistant/laura/holo.py`
- Test: `assistant/tests/test_holo.py`

**Interfaces:**
- Consumes: `holo_preview.tipo_de`, `holo_preview.preparar`, `holo_preview.pagina_pdf` (Task 1).
- Produces:
  - `@dataclass Item(n:int, ruta:str, nombre:str, tipo:str, tamano:int=0, mtime:float=0.0, enviado:bool=False)`
  - `class Escena(emit: Callable[..., None] | None = None, ttl: float = 600.0, reloj: Callable[[], float] = time.monotonic, preparar: Callable[[str, str], dict] = holo_preview.preparar)`
    - `listar(titulo: str, entradas: list[dict]) -> list[Item]` — `entradas` son `candidatos` de warp (`ruta`, `nombre`, `tamano`, `modificado`); máx. 12; renumera desde 1; cierra los visores anteriores; `seleccionado=None`; emite `op="list"`, `panel`=lista.
    - `abrir(numeros: list[int] | None = None, ruta: str | None = None) -> dict` — `{"ok":True,"abiertos":[Item…]}` o `{"ok":False,"error":"Solo hay N."}`/`"No hay ninguna lista en pantalla."`. Una `ruta` suelta se añade como item `n = len(items)+1` (y crea la lista si no había, con título = carpeta). Si el visor ya existe no se duplica. `seleccionado` = último abierto. Emite un `op="open"` por visor nuevo (con `panel`).
    - `cerrar(numeros: list[int] | None = None, todo: bool = False) -> int` — `todo` → vacía la escena entera (items incluidos) y emite `op="clear"`; si no, cierra visores `v<n>` y emite `op="close"` con `ids`. Devuelve cuántos paneles cerró. Si tras cerrar no queda la lista ni visores, la escena se vacía.
    - `cerrar_panel(pid: str) -> int` — `"lista"` equivale a `todo=True`; `"v3"` cierra ese visor.
    - `seleccionar(n: int) -> Item | None` — emite `op="select"`.
    - `resolver(n: int | None) -> Item | None` — `None` → item seleccionado.
    - `marcar_enviado(n: int) -> None` — emite `op="sent"`, `ids=["v<n>"]`.
    - `pagina(pid: str, p: int) -> dict` — solo visores PDF; acota `1..paginas`; actualiza `payload.src`/`pagina`; emite `op="page"`.
    - `contexto() -> str` — `""` si vacía o caducada; si no, p. ej. `"En pantalla (hologramas): lista «Descargas»: 1 WhatsApp 21.04.jpg · 2 practica3.pdf. Abiertos: 1, 2. Seleccionado: 2 («esa»)."`. Nombres de más de 40 caracteres se recortan con «…».
    - `caducar() -> bool` — si `reloj() - ultimo_uso > ttl` y hay escena: la vacía, emite `clear`, devuelve `True`.
    - `snapshot() -> dict` — el evento completo con `op="snapshot"` (lo usa el bus para lectores nuevos).
    - `control(cmd: str, arg: str) -> dict` — `holo-open <n>`, `holo-select <n>`, `holo-close <pid|all>`, `holo-send <n>`, `holo-page <pid> <p>`, `holo-ext <n>`. `holo-send` llama a `enviar_por_warp(n)` (atributo inyectable, por defecto importa `tools.warp` y llama `warp("archivo", ruta=…)`, y si va bien `marcar_enviado`). `holo-ext` ejecuta `xdg-open` con `subprocess.Popen` (atributo inyectable `abrir_externo`). Respuesta `{"ok":bool,…}`; comando desconocido → `{"ok":False,"error":…}`.
  - `escena() -> Escena` — singleton del módulo, creado la primera vez con `emit=config.bus.emit` (import perezoso de `.config` dentro de la función, para que los tests no carguen la config).
  - Todas las operaciones con un `threading.RLock`; cada mutación actualiza `ultimo_uso`.

- [ ] **Step 1: Write the failing tests**

```python
"""Escena de hologramas de Laura: numeración, «esa», eventos y caducidad."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura.holo import Escena  # noqa: E402


def cand(*nombres):
    return [{"ruta": f"/h/Descargas/{n}", "nombre": n, "tamano": 10, "modificado": 1.0} for n in nombres]


class Bus:
    def __init__(self):
        self.ev = []

    def __call__(self, **e):
        self.ev.append(e)

    def ops(self):
        return [e["op"] for e in self.ev]


def nueva(**kw):
    bus = Bus()
    t = {"now": 0.0}
    e = Escena(emit=bus, reloj=lambda: t["now"], preparar=lambda r, tipo: {"tipo": tipo, "src": r}, **kw)
    return e, bus, t


def test_listar_numera_y_emite():
    e, bus, _ = nueva()
    items = e.listar("Descargas", cand("a.png", "b.pdf", "c.md"))
    assert [(i.n, i.tipo) for i in items] == [(1, "imagen"), (2, "pdf"), (3, "texto")]
    ev = bus.ev[-1]
    assert ev["type"] == "holo" and ev["op"] == "list" and ev["panel"]["id"] == "lista"
    assert [p["id"] for p in ev["paneles"]] == ["lista"] and len(ev["items"]) == 3


def test_listar_tope_12():
    e, _, _ = nueva()
    assert len(e.listar("X", cand(*[f"{i}.txt" for i in range(20)]))) == 12


def test_abrir_varios_y_esa():
    e, bus, _ = nueva()
    e.listar("Descargas", cand("a.png", "b.pdf"))
    r = e.abrir([1, 2])
    assert r["ok"] and [i.n for i in r["abiertos"]] == [1, 2]
    assert bus.ops()[-2:] == ["open", "open"]
    assert bus.ev[-1]["panel"] == {"id": "v2", "kind": "visor", "titulo": "b.pdf", "item_n": 2,
                                  "payload": {"tipo": "pdf", "src": "/h/Descargas/b.pdf"}}
    assert e.resolver(None).n == 2          # «esa» = la última abierta
    e.seleccionar(1)
    assert e.resolver(None).n == 1 and bus.ops()[-1] == "select"


def test_abrir_fuera_de_rango_y_sin_lista():
    e, _, _ = nueva()
    assert e.abrir([1]) == {"ok": False, "error": "No hay ninguna lista en pantalla."}
    e.listar("D", cand("a.png"))
    assert e.abrir([5]) == {"ok": False, "error": "Solo hay 1."}


def test_abrir_no_duplica():
    e, bus, _ = nueva()
    e.listar("D", cand("a.png"))
    e.abrir([1])
    e.abrir([1])
    assert [p["id"] for p in bus.ev[-1]["paneles"]].count("v1") == 1


def test_abrir_ruta_suelta_sin_lista():
    e, _, _ = nueva()
    r = e.abrir(ruta="/h/Imágenes/foto.jpg")
    assert r["ok"] and r["abiertos"][0].n == 1
    assert e.snapshot()["paneles"][0]["id"] == "lista"


def test_nueva_lista_cierra_visores():
    e, bus, _ = nueva()
    e.listar("D", cand("a.png", "b.pdf"))
    e.abrir([1])
    e.listar("Documentos", cand("x.md"))
    assert [p["id"] for p in bus.ev[-1]["paneles"]] == ["lista"] and e.resolver(None) is None


def test_cerrar_y_vaciar():
    e, bus, _ = nueva()
    e.listar("D", cand("a.png", "b.pdf"))
    e.abrir([1, 2])
    assert e.cerrar([1]) == 1 and bus.ev[-1]["op"] == "close" and bus.ev[-1]["ids"] == ["v1"]
    assert e.cerrar(todo=True) == 2 and bus.ev[-1]["op"] == "clear"
    assert e.contexto() == "" and e.snapshot()["items"] == []


def test_contexto():
    e, _, _ = nueva()
    e.listar("Descargas", cand("WhatsApp 21.04.jpg", "practica3.pdf"))
    e.abrir([2])
    c = e.contexto()
    assert "Descargas" in c and "1 WhatsApp 21.04.jpg" in c and "Abiertos: 2" in c and "Seleccionado: 2" in c


def test_caducidad():
    e, bus, t = nueva(ttl=600)
    e.listar("D", cand("a.png"))
    t["now"] = 599
    assert not e.caducar()
    t["now"] = 1300
    assert e.caducar() and bus.ev[-1]["op"] == "clear" and e.contexto() == ""


def test_control_y_envio():
    e, bus, _ = nueva()
    enviados = []
    e.enviar_por_warp = lambda n: (enviados.append(n), e.marcar_enviado(n), {"ok": True})[-1]
    e.listar("D", cand("a.png", "b.pdf"))
    assert e.control("holo-open", "2")["ok"] and e.resolver(None).n == 2
    assert e.control("holo-select", "1")["ok"] and e.resolver(None).n == 1
    assert e.control("holo-send", "1")["ok"] and enviados == [1]
    assert bus.ev[-1]["op"] == "sent" and bus.ev[-1]["items"][0]["enviado"]
    assert e.control("holo-close", "v2")["ok"]
    assert e.control("holo-close", "all")["ok"] and bus.ev[-1]["op"] == "clear"
    assert not e.control("holo-nada", "")["ok"]


def test_pagina_pdf(monkeypatch):
    from laura import holo
    e, bus, _ = nueva()
    e.preparar = lambda r, t: {"tipo": "pdf", "src": "/c/p1.png", "pagina": 1, "paginas": 3}
    monkeypatch.setattr(holo.holo_preview, "pagina_pdf", lambda ruta, p: f"/c/p{p}.png")
    e.listar("D", cand("b.pdf"))
    e.abrir([1])
    e.pagina("v1", 9)
    ev = bus.ev[-1]
    assert ev["op"] == "page" and ev["panel"]["payload"]["pagina"] == 3 and ev["panel"]["payload"]["src"] == "/c/p3.png"
```

- [ ] **Step 2:** `python3 -m pytest -q tests/test_holo.py` → FAIL.
- [ ] **Step 3:** Implementar `holo.py`. Los `Item` se serializan con `dataclasses.asdict`. `Panel` es un `dict` simple. El tipo de cada item sale de `holo_preview.tipo_de(ruta)`. El payload del visor se calcula con `self.preparar(ruta, tipo)` en el momento de abrir.
- [ ] **Step 4:** `python3 -m pytest -q tests` → todo verde.

---

### Task 3: tools, warp y cableado del daemon

**Agente:** Gemini 3.8 Flash (high)

**Files:**
- Create: `assistant/laura/tools/holo.py`, `assistant/tests/test_tools_holo.py`
- Modify: `assistant/laura/tools/warp.py`, `assistant/laura/tools/__init__.py` (línea del `from . import …`), `assistant/laura/events.py`, `assistant/laura/llm.py` (`refresh_system`), `assistant/laura/daemon.py` (`control()` y `janitor()`), `assistant/config.toml` (`system_prompt`)

**Interfaces:**
- Consumes: `holo.escena()`, `Escena.listar/abrir/cerrar/resolver/marcar_enviado/contexto/caducar/snapshot/control` (Task 2); `holo_preview.limpiar_cache` (Task 1).
- Produces: tools `mostrar_archivos(carpeta=None, consulta=None)`, `abrir(numeros=None, ruta=None)`, `cerrar_holo(numeros=None, todo=False)`; `warp(..., numero=None)`; `EventBus.on_connect: list[Callable[[], dict | None]]`.

Detalles:

1. **`tools/holo.py`**
   - `mostrar_archivos`: sin `consulta` → `warp._warp("listar", *([carpeta] if carpeta else []))`; con consulta → `warp._warp("buscar", consulta, *(["--carpeta", carpeta] if carpeta else []))` y, si la carpeta no da candidatos, reintenta sin carpeta (igual que hace `warp`). Título: `Path(d["carpeta"]).name` si existe, o `f"«{consulta}»"`. Llama a `escena().listar(titulo, candidatos)`. Devuelve `{"ok":True,"decir":…, "resumen":f"{titulo} en pantalla", "n":len}`. `decir`: vacío → `"No hay nada."`; si no → `f"Tienes {num_palabra(n)} cosas; la más reciente es {nombre_corto(items[0])}."` (con `num_palabra` de 1 a 12 en letra: «una», «dos»… y «una cosa» en singular). `nombre_corto` quita la extensión y recorta a 40 caracteres. Icono `folder_open`.
     Descripción: `"Enseña en pantalla (hologramas) los archivos de una carpeta o los que coinciden con una búsqueda: «lístame/enséñame las descargas», «qué hay en Documentos», «busca el pdf de redes». Abre un panel con la lista numerada. Para ENVIAR al móvil usa warp."`
   - `abrir`: `escena().abrir(numeros, ruta)`; ok → `decir` = `"Ahí lo tienes."` (1) o `"Ahí los tienes."` (varios), `resumen` = `"Abriendo " + ", ".join(nombres)`. Icono `visibility`. Descripción: `"Abre en pantalla uno o varios archivos de la lista que se ve («ábreme la 1 y la 2», «enséñame esa captura», «abre el pdf»): «numeros» de la lista; o «ruta» si viene de otra herramienta."` Parámetro `numeros`: `{"type":"array","items":{"type":"integer"}}`.
   - `cerrar_holo`: `n = escena().cerrar(numeros, todo or not numeros)`; `decir` `"Hecho."`. Icono `close`. Descripción: `"Cierra hologramas: «cierra eso / cierra todo» (todo=true) o «cierra la 2» (numeros)."`
2. **`tools/warp.py`**
   - Añadir al esquema `"numero": {"type":"integer","description":"archivo: número de la lista que se ve en pantalla («envía la 2», «manda esa»)"}` y el parámetro `numero: int | None = None` a la función. Añadir a la descripción: `" Si hay archivos en pantalla, «envía la N / esa al móvil» = archivo con «numero» (sin numero = el seleccionado)."`
   - Al principio de `warp()`, si `accion == "archivo"` y no hay `ruta` y (hay `numero` o no hay `consulta`): `it = escena().resolver(numero)`; si `it` → `ruta = it.ruta` y recordar `n = it.n`; si no y `numero` → `return {"ok":False,"error":"no hay nada con ese número en pantalla"}`.
   - Tras un envío correcto de `archivo` con `n` resuelto → `escena().marcar_enviado(n)`.
   - En `listar` y `buscar` con `ok` y candidatos → también `escena().listar(titulo, candidatos)` (mismo título que `mostrar_archivos`), envuelto en `try/except Exception` para que un fallo de la escena nunca rompa warp.
   - Importar `from ..holo import escena` dentro de las funciones (perezoso).
3. **`tools/__init__.py`**: añadir `holo` al final del `from . import …`.
4. **`events.py`**: en `__init__`, `self.on_connect: list = []`. En `_accept_loop`, tras mandar el `state`, para cada `fn` en `self.on_connect`: `obj = fn()` y, si no es `None`, `self._send(conn, obj)` (cada uno en `try/except Exception`). Actualizar el docstring con el evento `holo`.
5. **`llm.py` · `refresh_system`**: tras `extra`, `try: ctx = escena().contexto()` (import perezoso `from .holo import escena`) `except Exception: ctx = ""`; si `ctx`: `extra += "\n\n" + ctx`.
6. **`daemon.py`**: en `main()`, tras crear la escena por primera vez, `from .holo import escena`, `from .holo_preview import limpiar_cache`; `limpiar_cache()`; `bus.on_connect.append(lambda: escena().snapshot() if escena().snapshot()["paneles"] else {"type":"holo","op":"clear","items":[],"paneles":[],"seleccionado":None,"panel":None,"ids":None})`. En `control()`, antes de `job-dismiss`: `if cmd.startswith("holo-"): return escena().control(cmd, arg)`. En `janitor()`: `escena().caducar()` en su propio `try/except`.
7. **`config.toml`**: añadir al final del párrafo «Guía:» del `system_prompt`: `«Lístame/enséñame/qué hay en una carpeta o busca un archivo para verlo» = mostrar_archivos; «abre/enséñame la N, esa» = abrir; «cierra eso» = cerrar_holo; «envía la N/esa al móvil» = warp archivo con numero. «Esa», «la 2» se refieren a lo que hay en pantalla.`

- [ ] **Step 1: Write the failing tests** (`assistant/tests/test_tools_holo.py`)

```python
"""Tools de hologramas + warp con número, contra un warp falso y una escena con bus de prueba."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from laura import holo  # noqa: E402
from laura.tools import holo as th  # noqa: E402
from laura.tools import warp as w  # noqa: E402


@pytest.fixture
def entorno(monkeypatch):
    ev = []
    esc = holo.Escena(emit=lambda **e: ev.append(e), preparar=lambda r, t: {"tipo": t, "src": r})
    monkeypatch.setattr(holo, "escena", lambda: esc)
    llamadas = []
    resp = {"listar": {"ok": True, "carpeta": "/h/Descargas", "candidatos": [
        {"ruta": "/h/Descargas/WhatsApp 21.04.jpg", "nombre": "WhatsApp 21.04.jpg", "tamano": 1, "modificado": 1},
        {"ruta": "/h/Descargas/practica3.pdf", "nombre": "practica3.pdf", "tamano": 1, "modificado": 1}]},
        "archivo": {"ok": True, "enviado": {"nombre": "x"}}}

    def falso(*args, entrada=None):
        llamadas.append(args)
        return resp.get(args[0], {"ok": True, "candidatos": []})
    monkeypatch.setattr(w, "_warp", falso)
    return esc, ev, llamadas


def test_mostrar_archivos(entorno):
    esc, ev, llamadas = entorno
    r = th.mostrar_archivos(carpeta="Descargas")
    assert r["ok"] and r["n"] == 2 and r["decir"] == "Tienes dos cosas; la más reciente es WhatsApp 21.04."
    assert llamadas[0] == ("listar", "Descargas") and ev[-1]["op"] == "list"


def test_abrir_y_enviar_esa(entorno):
    esc, ev, llamadas = entorno
    th.mostrar_archivos(carpeta="Descargas")
    assert th.abrir(numeros=[1])["decir"] == "Ahí lo tienes."
    r = w.warp("archivo")                       # «envía esa al móvil»
    assert r["ok"] and llamadas[-1][:2] == ("archivo", "/h/Descargas/WhatsApp 21.04.jpg")
    assert ev[-1]["op"] == "sent"


def test_enviar_por_numero(entorno):
    esc, ev, llamadas = entorno
    th.mostrar_archivos()
    assert w.warp("archivo", numero=2)["ok"] and llamadas[-1][1] == "/h/Descargas/practica3.pdf"
    assert not w.warp("archivo", numero=7)["ok"]


def test_warp_listar_tambien_rellena_la_escena(entorno):
    esc, ev, _ = entorno
    w.warp("listar", carpeta="Descargas")
    assert esc.resolver(1).nombre == "WhatsApp 21.04.jpg"


def test_cerrar_holo(entorno):
    esc, ev, _ = entorno
    th.mostrar_archivos()
    th.abrir(numeros=[1, 2])
    assert th.cerrar_holo()["ok"] and ev[-1]["op"] == "clear"


def test_registradas():
    from laura.tools import REGISTRY
    assert {"mostrar_archivos", "abrir", "cerrar_holo"} <= set(REGISTRY)
    assert "numero" in REGISTRY["warp"].schema["function"]["parameters"]["properties"]


def test_bus_on_connect(tmp_path):
    import socket
    from laura.events import EventBus
    bus = EventBus(str(tmp_path / "ev.sock"))
    bus.on_connect.append(lambda: {"type": "holo", "op": "snapshot"})
    bus.start()
    c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    c.connect(str(tmp_path / "ev.sock"))
    c.settimeout(2)
    assert b'"op": "snapshot"' in c.recv(4096)
    bus.close()
```

- [ ] **Step 2:** `python3 -m pytest -q tests/test_tools_holo.py` → FAIL.
- [ ] **Step 3:** Implementar los puntos 1–7.
- [ ] **Step 4:** `python3 -m pytest -q tests` → todo verde (incluidos `test_warp.py` antiguos).
- [ ] **Step 5:** Humo del daemon: `python3 -c "import sys; sys.path.insert(0,'.'); from laura import daemon"` sin errores.

---

### Task 4: QML — estado, ventana, colocación y demo

**Agente:** Gemini 4 Argon (medium)

**Files:**
- Create: `configs/quickshell/caelestia/modules/assistant/HoloState.qml`, `configs/quickshell/caelestia/modules/holo/HoloOverlay.qml`, `HoloLayer.qml`, `HoloPlacer.js`, `HoloLinks.qml`, y un `HoloPanel.qml` **provisional** (un `Rectangle` con borde `m3primary`, título y un `Loader` de contenido; la Task 5 lo sustituye entero)
- Modify: `configs/quickshell/caelestia/modules/assistant/Laura.qml` (`case "holo"` en `_handle`; función pública `ctrl(cmd)` que llama a `_ctrl(cmd, null)`), `configs/quickshell/caelestia/shell.qml` (`import "modules/holo"` y `HoloOverlay {}` justo debajo de `Assistant {}`)

**Interfaces:**
- Consumes: el evento `holo` de las Global Constraints.
- Produces (los usan las Tasks 5 y 6):
  - `HoloState` (singleton en `qs.modules.assistant`):
    `property var items: []`, `property var paneles: []`, `property int seleccionado: -1`, `readonly property bool activo: paneles.length > 0`,
    `signal opened(string pid)`, `signal closed(var ids)`, `signal sent(string pid)`, `signal cleared()`,
    `function handle(ev)`, `function item(n): var` (o `null`), `function abrir(n)`, `function seleccionar(n)`, `function cerrar(pid)`, `function cerrarTodo()`, `function enviar(n)`, `function pagina(pid, p)`, `function externo(n)`, `function demo()`.
    Las funciones de acción llaman a `Laura.ctrl("holo-open " + n)` etc. **No** tocan el modelo localmente: el daemon responde con el evento y `handle` actualiza. `demo()` llama a `handle` con eventos falsos encadenados (lista de 8 items de Descargas variados; tras 1,2 s abre un visor de imagen con `src` = la imagen más reciente de `~/Imágenes` o un `file:///usr/share/pixmaps/archlinux-logo.png` si no hay, y un visor de texto con contenido de ejemplo), sin daemon.
    `IpcHandler { target: "holo"; function demo(): void; function clear(): void }`.
  - `HoloPlacer.js` (`.pragma library`): `function place(W, H, ocupados, w, h, rnd) -> {x, y, rot}`. `ocupados` = lista de `{x,y,w,h}` (incluye la píldora: centrada abajo, 30 % del ancho × 12 % del alto, y un margen de 48 px en todo el borde). Algoritmo: rejilla 12×8; prueba todas las posiciones de celda donde cabe `w×h` sin intersecar ningún ocupado (con 24 px de separación); puntúa = distancia mínima a los ocupados (más hueco, mejor) + `rnd()*80`; devuelve la mejor; `rot = (rnd()*4 - 2)` grados. Si no cabe en ningún sitio, devuelve la posición con menos solape y `w,h` sin cambiar. Determinista si `rnd` lo es (para probarlo).
  - Tamaños por panel (función `HoloPlacer.size(panel, W, H) -> {w,h}`): lista `min(460, 0.32W) × (64 + 38*items)`; imagen: encajar `payload.w/h` en `0.30W × 0.62H` (si 0, `0.26W × 0.5H`); pdf `0.30W × 0.74H`; texto `0.34W × 0.56H`; video `0.40W × 0.45H`; audio `0.30W × 0.16H`; otro `0.22W × 0.20H`.
  - `HoloLayer.qml`: `PanelWindow` por pantalla, `WlrLayershell.layer: WlrLayer.Overlay`, `exclusionMode: Ignore`, anclada a los cuatro lados, `color: "transparent"`, `visible: HoloState.activo && (Hypr.focusedMonitor?.name === modelData.name) || cerrando` (con `cerrando` = true durante 450 ms tras `cleared` para la animación de salida). `WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : None`; `Keys.onEscapePressed` → `HoloState.cerrarTodo()`. Velo: `Rectangle` negro `opacity 0.62` + `RadialGradient`-equivalente (un `Rectangle` con `gradient` vertical de `Qt.alpha(m3primary, 0.18)` a transparente en el 45 % inferior) + `Image { fillMode: Image.Tile; source: "assets/dots.png"; opacity: 0.25 }`. Clic en el velo vacío = no hace nada (solo Esc / botones cierran). Un `Repeater` sobre `HoloState.paneles` crea `HoloPanel { panel: modelData; layer: root }` y guarda en `posiciones[id]` el resultado de `HoloPlacer.place` (calculado **una vez** al aparecer el id; la lista va siempre en `x = 0.08W`, centrada en vertical, y al abrir visores se desplaza con `Behavior on x`). `HoloLinks` encima del velo y debajo de los paneles.
  - `HoloLinks.qml`: `Shape` con un `ShapePath` (`strokeStyle: ShapePath.DashLine`, `strokeColor: Qt.alpha(m3primary, 0.7)`, `fillColor: "transparent"`) por visor abierto: curva cúbica desde el borde derecho de la fila `n` de la lista (`lista.y + 64 + 38*(n-1) + 19`) hasta el borde más cercano del visor. Se recalcula cuando cambian posiciones (bindings).
  - `HoloPanel.qml` (contrato que la Task 5 debe respetar): `required property var panel`, `property var layer`, `property real targetX`, `property real targetY`, `property real targetRot`, `property point origin` (centro de la píldora: `(W/2, H - 0.06H)`), `function sendAway()`, `function closeAway()`. Elige el contenido con un `Loader` por `panel.kind`/`panel.payload.tipo`: `HoloList`, `HoloImage`, `HoloPdf`, `HoloMedia`, `HoloText`, `HoloOther` (cada uno con `required property var panel`). Mientras la Task 6 no exista, que el `Loader` use un `Text` con `panel.titulo`.

- [ ] **Step 1:** Escribir `HoloPlacer.js` y probarlo con `qml`-free: `node -e` cargando el fichero quitando la línea `.pragma library` (`sed 1d HoloPlacer.js > /tmp/claude-…/placer.js`) y comprobando que 8 colocaciones seguidas en 2560×1440 no se solapan entre sí ni con la píldora. Guardar ese script de prueba en `configs/quickshell/caelestia/modules/holo/test_placer.mjs`.
- [ ] **Step 2:** `HoloState.qml` + cambios en `Laura.qml` + `HoloOverlay`/`HoloLayer`/`HoloLinks`/`HoloPanel` provisional + `shell.qml`.
- [ ] **Step 3:** Generar `assets/dots.png` (26×26, punto blanco de 1,2 px de radio en el centro, resto transparente) y `assets/scan.png` (1×3: una fila blanca alfa 0,07 y dos transparentes) con Pillow.
- [ ] **Step 4:** Sincronizar `cp -r configs/quickshell/caelestia/modules/holo ~/.config/quickshell/caelestia/modules/` y los archivos tocados de `modules/assistant/` y `shell.qml`; reiniciar el shell; `INFO: Configuration Loaded` sin errores; `qs -c caelestia ipc call holo demo` → aparecen la lista y dos visores; `qs -c caelestia ipc call holo clear` → se van. Captura con `grim` para el orquestador en el scratchpad que se te indique. **No mover el ratón ni hacer clics** (lo comparten otros agentes).

---

### Task 5: chasis del holograma y animaciones (diseño)

**Agente:** el orquestador (Claude)

**Files:** sustituye `configs/quickshell/caelestia/modules/holo/HoloPanel.qml`; ajusta `HoloLayer.qml` (velo) si hace falta.

Lo que tiene que quedar (spec, sección «Aspecto»):
- Cristal: `Rectangle` `radius: Tokens.rounding.large`, `color: Qt.alpha(m3surfaceContainer, 0.86)`, `border { width: 1; color: Qt.alpha(m3primary, 0.55) }`; halo = un segundo `Rectangle` detrás, 10 px más grande, `color: "transparent"`, `border.color: Qt.alpha(m3primary, 0.18)`, `border.width: 8`, `radius + 10` (sin sombras ni blur); reflejo superior = gradiente `Qt.alpha(m3primary, 0.12)` → transparente en el 30 % superior; escaneo = `Image { fillMode: Tile; source: "assets/scan.png"; opacity: 0.6 }` encima de todo, recortado con `clip` en el rectángulo redondeado.
- Cabecera: icono `MaterialIcon` (o número en círculo `m3primary` para visores), título en mayúsculas `letterSpacing 1.2`, `m3primary`; meta a la derecha `m3onSurfaceVariant`; botón cerrar (`close`) → `HoloState.cerrar(panel.id)`.
- Nacimiento (una sola vez): rayo = `Rectangle` de 2 px que crece desde `origin` hacia el destino (rotado) en 180 ms y se desvanece; el panel arranca en `origin` a escala 0,15 y opacidad 0, y vuela al destino con `ParallelAnimation` (x/y `OutCubic` 420 ms, escala `OutBack` 420 ms, opacidad 220 ms, rotación hasta `targetRot`); parpadeo de holograma al llegar (opacidad 1 → 0,55 → 1 en 120 ms).
- `sendAway()`: escala X 0,3 / Y 1,4 + vuelo a `(W/2, -40)` en 380 ms `InCubic` + opacidad a 0 (el agujero negro real lo abre `warp` solo).
- `closeAway()`: vuelta a `origin` con escala 0,15 y opacidad 0 en 300 ms; los paneles en cascada (retardo 60 ms × índice) en `cleared`.
- Arrastre: `DragHandler` en la cabecera; al soltar con `y < 60` → `HoloState.enviar(panel.item_n)`. Clic en el cuerpo de un visor → `HoloState.seleccionar(panel.item_n)`; el seleccionado lleva el borde a alfa 0,9.
- Clic derecho en cualquier panel → `HoloState.cerrar(panel.id)`.
- Ninguna animación en bucle: todo son animaciones de una sola vez.

- [ ] Implementar, sincronizar, reiniciar, `ipc call holo demo`, capturar y comparar con la maqueta aprobada (`.superpowers/brainstorm/…/content/hud-ecosistema-v2.html`).

---

### Task 6: contenidos de los paneles

**Agente:** Gemini 3.8 Flash (high)

**Files:** Create `configs/quickshell/caelestia/modules/holo/HoloList.qml`, `HoloImage.qml`, `HoloPdf.qml`, `HoloMedia.qml`, `HoloText.qml`, `HoloOther.qml`.

**Interfaces:**
- Consumes: `HoloState` (Task 4), `required property var panel` en cada componente; `panel.payload` según la tabla de la Task 1.
- Cada componente ocupa `anchors.fill: parent` (el chasis le da el hueco bajo la cabecera) y usa solo `Colours.palette.m3*` y `Tokens`.

Detalles:
- **HoloList**: `ListView` sobre `HoloState.items`; fila de 38 px: número en píldora (`m3primary` al 18 % de fondo; si el item tiene visor abierto, fondo `m3primary` sólido y número en `m3onPrimary`), miniatura 22×16 redondeada (imagen real con `sourceSize` 44×32 para `tipo === "imagen"`; para el resto un `Rectangle` con color por tipo: pdf `m3error`, texto `m3outline`, video/audio `m3tertiary`, otro `m3secondary`), nombre (elide derecha), y a la derecha la fecha relativa («hace 3 min», «ayer», «lun») calculada de `mtime`, o «→ móvil ✓» en `m3primary` si `enviado`. Clic → `HoloState.abrir(n)`. Pie con dos chips: «di «abre la 2»» y «o haz clic».
- **HoloImage**: `Image { asynchronous: true; fillMode: PreserveAspectFit; source: "file://" + payload.src }` dentro de un `Flickable`; rueda = zoom 1×–5× centrado en el cursor; arrastrar = mover cuando hay zoom; doble clic = volver a 1×.
- **HoloPdf**: la imagen de `payload.src` (página ya renderizada) como en HoloImage sin zoom; abajo «pág N/M»; rueda hacia abajo/arriba → `HoloState.pagina(panel.id, N±1)` (con un `Timer` de 250 ms para no saturar).
- **HoloMedia**: `import QtMultimedia`; `MediaPlayer` + `VideoOutput` (vídeo) o solo `AudioOutput` con una barra de onda falsa estática (audio). Arranca en pausa mostrando `payload.poster`; clic = play/pausa; barra de progreso fina `m3primary`; `Component.onDestruction: player.stop()`.
- **HoloText**: `Flickable` + `TextEdit { readOnly: true; textFormat: payload.formato === "markdown" ? TextEdit.MarkdownText : TextEdit.PlainText; font.family: formato === "mono" ? "JetBrains Mono" : Tokens.font.family.sans (o el que use el resto del shell); wrapMode: Wrap; selectByMouse: true; color: m3onSurface }`; si `truncado`, una línea final «… (recortado)» en `m3onSurfaceVariant`.
- **HoloOther**: icono grande `payload.icono`, nombre, `payload.aviso` si lo hay, y botón «Abrir con su programa» → `HoloState.externo(panel.item_n)`.

- [x] Implementar; sincronizar; reiniciar; ampliar `HoloState.demo()` para que abra también un PDF (`payload.src` = una imagen cualquiera, `paginas: 12`), un texto markdown y un `otro`; capturar con `grim`. Sin ratón.

---

### Task 7: examen del modelo, prueba real y documentación

**Agente:** el orquestador (Claude), con Gemini 3.8 Flash (low) para redactar las frases si hace falta.

- [ ] Añadir a `assistant/eval/frases.toml` un bloque `# ---------- hologramas ----------` con, como mínimo:
  - «lístame las descargas» → `mostrar_archivos` (`carpeta = "descargas"`)
  - «enséñame qué hay en documentos» → `mostrar_archivos` (`carpeta = "documentos"`)
  - «búscame el pdf de la práctica de redes» → `mostrar_archivos` (`consulta = "redes"`)
  - «ábreme la uno y la dos» → `abrir`
  - «enséñame la tercera» → `abrir`
  - «envía esa al móvil» → `warp` (`accion = "archivo"`)
  - «manda la dos al móvil» → `warp` (`accion = "archivo"`, `numero = 2`)
  - «cierra todo eso» → `cerrar_holo`
  - trampa: «qué hora es» → `[]` sin tools de holo.
- [ ] `cd assistant && python3 eval/run.py` (ver `eval/README.md`) y comparar con el último resultado de `qwen3:4b-instruct`: la nota global no debe bajar más de 2 puntos; las frases de holo deben acertar ≥ 7/9. Si falla, ajustar descripciones de tools / línea del prompt.
- [ ] Reiniciar el daemon (`systemctl --user restart laura`) y probar por voz/texto: `laura-toggle` o el comando de control `ask lístame las descargas`, luego `ask abre la 1`, `ask envía esa al móvil` (envía de verdad: avisar a Alberto antes), `ask cierra todo`.
- [ ] CPU en reposo: con la escena cerrada, `top -b -n 2 -p $(pgrep -f "qs -c caelestia")` ≈ igual que antes.
- [ ] Escribir `docs/LAURA-HOLO.md` (qué se puede decir, ratón, comandos `holo-*`, `ipc call holo demo|clear`, caché y límites) y enlazarlo desde `assistant/README.md`.
- [ ] Merge de `feat/laura-holo` a `main`; tarea del backlog con `tasks-index`; línea en la bitácora de `vault/🎯 Hoy.md`.
