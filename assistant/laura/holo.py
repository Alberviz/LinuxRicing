"""Escena de hologramas de Laura: estado, eventos, contexto y socket de control."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
import subprocess
import threading
import time
import traceback
from typing import Callable

from . import archivos, holo_preview


def _log(msg: str) -> None:
    """Traza en el log del daemon (si no hay config, p. ej. en tests, a stdout)."""
    try:
        from .config import log
        log(msg)
    except Exception:  # noqa: BLE001
        print("[laura]", msg, flush=True)


def _quien() -> str:
    """Cadena de llamadas que han llevado hasta aquí (para saber qué vació la escena)."""
    return " <- ".join(f.name for f in reversed(traceback.extract_stack(limit=6)[:-2]))


@dataclass
class Item:
    n: int
    ruta: str
    nombre: str
    tipo: str
    tamano: int = 0
    mtime: float = 0.0
    enviado: bool = False


class Escena:
    """Gestiona los archivos y paneles holográficos activos en la pantalla."""

    def __init__(
        self,
        emit: Callable[..., None] | None = None,
        ttl: float = 600.0,
        reloj: Callable[[], float] = time.monotonic,
        preparar: Callable[[str, str], dict] = holo_preview.preparar,
    ) -> None:
        self._lock = threading.RLock()
        self.emit = emit
        self.ttl = ttl
        self.reloj = reloj
        self.preparar = preparar
        self.items: list[Item] = []
        self.paneles: dict[str, dict] = {}
        self.seleccionado: int | None = None
        self.ultimo_uso: float = self.reloj()
        self.enviar_por_warp: Callable[[int], dict] = self._enviar_por_warp_default
        self.abrir_externo: Callable[[str], dict] = self._abrir_externo_default
        self.listador: Callable[[str], dict] = self._listar_default
        self.carpeta: str | None = None        # carpeta de la lista que se ve (para relistar tras operar)
        self.retraso_relistado: float = 0.9    # deja que se vea la animación antes de relistar

    def _tocar(self) -> None:
        """Actualiza la marca de tiempo de última actividad."""
        self.ultimo_uso = self.reloj()

    def _emit(
        self,
        op: str,
        panel: dict | None = None,
        ids: list[str] | None = None,
        **extra,
    ) -> None:
        """Emite un evento de holograma con el estado completo de la escena."""
        evento = {
            "type": "holo",
            "op": op,
            "items": [asdict(it) for it in self.items],
            "paneles": list(self.paneles.values()),
            "seleccionado": self.seleccionado,
            "panel": panel,
            "ids": ids,
            **extra,
        }
        if self.emit is not None:
            self.emit(**evento)

    def listar(self, titulo: str, entradas: list[dict], carpeta: str | None = None) -> list[Item]:
        """Crea o sustituye la lista de archivos, cerrando los visores abiertos.
        `carpeta` (si se conoce) permite relistar tras mover, borrar o renombrar."""
        with self._lock:
            self._tocar()
            self.carpeta = carpeta
            self.paneles.clear()
            self.items.clear()
            self.seleccionado = None

            panel_lista = {
                "id": "lista",
                "kind": "lista",
                "titulo": titulo,
                "item_n": None,
                "payload": {},
            }
            self.paneles["lista"] = panel_lista

            for idx, entrada in enumerate(entradas[:12], start=1):
                ruta = entrada.get("ruta", "")
                nombre = entrada.get("nombre") or Path(ruta).name
                tipo = holo_preview.tipo_de(ruta)
                tamano = int(entrada.get("tamano", 0))
                mtime = float(entrada.get("modificado", 0.0))
                self.items.append(
                    Item(
                        n=idx,
                        ruta=ruta,
                        nombre=nombre,
                        tipo=tipo,
                        tamano=tamano,
                        mtime=mtime,
                        enviado=False,
                    )
                )

            self._emit("list", panel=panel_lista)
            return list(self.items)

    def abrir(
        self,
        numeros: list[int] | None = None,
        ruta: str | None = None,
    ) -> dict:
        """Abre visores para los archivos especificados por número o ruta suelta."""
        with self._lock:
            self._tocar()

            if ruta is not None:
                p = Path(ruta)
                carpeta = p.parent.name or str(p.parent) or "Archivos"
                if "lista" not in self.paneles:
                    self.paneles["lista"] = {
                        "id": "lista",
                        "kind": "lista",
                        "titulo": carpeta,
                        "item_n": None,
                        "payload": {},
                    }

                item_existente = next((it for it in self.items if it.ruta == ruta), None)
                if item_existente is None:
                    n = len(self.items) + 1
                    tipo = holo_preview.tipo_de(ruta)
                    tamano = 0
                    mtime = 0.0
                    try:
                        st = p.stat()
                        tamano = st.st_size
                        mtime = st.st_mtime
                    except OSError:
                        pass
                    item_existente = Item(
                        n=n,
                        ruta=ruta,
                        nombre=p.name,
                        tipo=tipo,
                        tamano=tamano,
                        mtime=mtime,
                        enviado=False,
                    )
                    self.items.append(item_existente)
                numeros = [item_existente.n]

            if not self.items:
                return {"ok": False, "error": "No hay ninguna lista en pantalla."}

            if numeros is None:
                if self.seleccionado is not None:
                    numeros = [self.seleccionado]
                else:
                    return {"ok": False, "error": "No hay ninguna lista en pantalla."}

            for n in numeros:
                if n < 1 or n > len(self.items):
                    return {"ok": False, "error": f"Solo hay {len(self.items)}."}

            # Una carpeta no se «abre» como visor: se entra en ella y se lista su contenido
            carpetas = [self.items[n - 1] for n in numeros if self.items[n - 1].tipo == "carpeta"]
            if carpetas:
                if len(numeros) == len(carpetas):
                    return self.entrar(carpetas[0])
                numeros = [n for n in numeros if self.items[n - 1].tipo != "carpeta"]

            abiertos: list[Item] = []
            for n in numeros:
                item = self.items[n - 1]
                abiertos.append(item)
                vid = f"v{n}"
                if vid not in self.paneles:
                    payload = self.preparar(item.ruta, item.tipo)
                    panel = {
                        "id": vid,
                        "kind": "visor",
                        "titulo": item.nombre,
                        "item_n": item.n,
                        "payload": payload,
                    }
                    self.paneles[vid] = panel
                    self.seleccionado = item.n
                    self._emit("open", panel=panel)
                else:
                    self.seleccionado = item.n
                    self._emit("select")   # ya estaba abierto: pasa a ser «esa» y el QML lo trae al frente

            return {"ok": True, "abiertos": abiertos}

    def entrar(self, item: Item) -> dict:
        """Entra en una carpeta de la lista: la sustituye por su contenido."""
        d = self.listador(item.ruta)
        if not d.get("ok"):
            return {"ok": False, "error": d.get("error") or f"No puedo abrir {item.nombre}."}
        items = self.listar(item.nombre, d.get("candidatos") or [], carpeta=item.ruta)
        return {"ok": True, "abiertos": [], "carpeta": item.nombre, "n": len(items)}

    def cerrar(self, numeros: list[int] | None = None, todo: bool = False) -> int:
        """Cierra visores concretos o vacía la escena completa si todo=True."""
        with self._lock:
            self._tocar()

            if todo:
                cuantos = len(self.paneles)
                _log(f"holo: escena vaciada ({cuantos} paneles) por {_quien()}")
                self.paneles.clear()
                _log(f"holo: escena vaciada (sin paneles) por {_quien()}")
                self.items.clear()
                self.seleccionado = None
                self._emit("clear")
                return cuantos

            ids_cerrados: list[str] = []
            if numeros is not None:
                for n in numeros:
                    vid = f"v{n}"
                    if vid in self.paneles:
                        del self.paneles[vid]
                        ids_cerrados.append(vid)
                        if self.seleccionado == n:
                            self.seleccionado = None
            elif self.seleccionado is not None:
                vid = f"v{self.seleccionado}"
                if vid in self.paneles:
                    del self.paneles[vid]
                    ids_cerrados.append(vid)
                self.seleccionado = None

            # Si tras cerrar no queda ningún panel, la escena se vacía por completo
            if not self.paneles:
                _log(f"holo: escena vaciada (sin paneles) por {_quien()}")
                self.items.clear()
                self.seleccionado = None
                self._emit("clear")
            elif ids_cerrados:
                self._emit("close", ids=ids_cerrados)

            return len(ids_cerrados)

    def cerrar_panel(self, pid: str) -> int:
        """Cierra un panel por su identificador. 'lista' equivale a todo=True."""
        with self._lock:
            self._tocar()
            if pid in ("lista", "all"):
                return self.cerrar(todo=True)
            if pid.startswith("v") and pid[1:].isdigit():
                n = int(pid[1:])
                return self.cerrar([n])
            if pid in self.paneles:
                del self.paneles[pid]
                if not self.paneles:
                    self.items.clear()
                    self.seleccionado = None
                    self._emit("clear")
                else:
                    self._emit("close", ids=[pid])
                return 1
            return 0

    def seleccionar(self, n: int) -> Item | None:
        """Marca un elemento como seleccionado y emite el evento select."""
        with self._lock:
            self._tocar()
            if 1 <= n <= len(self.items):
                self.seleccionado = n
                self._emit("select")
                return self.items[n - 1]
            return None

    def resolver(self, n: int | None = None) -> Item | None:
        """Devuelve el elemento por número o el seleccionado si n es None."""
        with self._lock:
            if n is None:
                if self.seleccionado is not None and 1 <= self.seleccionado <= len(self.items):
                    return self.items[self.seleccionado - 1]
                return None
            if 1 <= n <= len(self.items):
                return self.items[n - 1]
            return None

    def marcar_enviado(self, n: int) -> None:
        """Marca un elemento como enviado y emite el evento sent."""
        with self._lock:
            self._tocar()
            if 1 <= n <= len(self.items):
                self.items[n - 1].enviado = True
                self._emit("sent", ids=[f"v{n}"])

    def pagina(self, pid: str, p: int) -> dict:
        """Cambia de página en un visor de PDF y emite el evento page."""
        with self._lock:
            self._tocar()
            panel = self.paneles.get(pid)
            if not panel or panel.get("payload", {}).get("tipo") != "pdf":
                return {"ok": False, "error": "No es un visor PDF o no existe."}

            payload = panel["payload"]
            paginas = payload.get("paginas", 1)
            p_acotada = max(1, min(p, paginas))

            item_n = panel.get("item_n")
            if item_n is None or not (1 <= item_n <= len(self.items)):
                return {"ok": False, "error": "Item asociado no encontrado."}

            item = self.items[item_n - 1]
            src = holo_preview.pagina_pdf(item.ruta, p_acotada)
            if src is None:
                return {"ok": False, "error": "No se pudo generar la página."}

            payload["pagina"] = p_acotada
            payload["src"] = src
            self._emit("page", panel=panel)
            return {"ok": True, "pagina": p_acotada, "paginas": paginas}

    def contexto(self) -> str:
        """Devuelve una síntesis textual de lo que hay en pantalla para el LLM."""
        with self._lock:
            if not self.items:
                return ""
            if self.reloj() - self.ultimo_uso > self.ttl:
                self.caducar()
                return ""

            panel_lista = self.paneles.get("lista")
            titulo = panel_lista["titulo"] if panel_lista else "Archivos"

            def _nombre_corto(nombre: str) -> str:
                if len(nombre) > 40:
                    return nombre[:39] + "…"
                return nombre

            items_str = " · ".join(f"{it.n} {_nombre_corto(it.nombre)}" for it in self.items)
            partes = [f"En pantalla (hologramas): lista «{titulo}»: {items_str}."]

            abiertos = [
                p["item_n"]
                for p in self.paneles.values()
                if p.get("kind") == "visor" and p.get("item_n") is not None
            ]
            if abiertos:
                abiertos_str = ", ".join(str(n) for n in sorted(abiertos))
                partes.append(f"Abiertos: {abiertos_str}.")

            if self.seleccionado is not None:
                partes.append(f"Seleccionado: {self.seleccionado} («esa»).")

            return " ".join(partes)

    # ------------------------------------------------------------ archivos (planes)

    def _quitar_panel(self, pid: str) -> None:
        """Quita un panel (con el lock tomado); si era el último, vacía la escena."""
        if pid not in self.paneles:
            return
        del self.paneles[pid]
        if not self.paneles:
            _log(f"holo: escena vaciada al quitar {pid} por {_quien()}")
            self.items.clear()
            self.seleccionado = None
            self._emit("clear")
        else:
            self._emit("close", ids=[pid])

    def mostrar_confirmacion(self, plan) -> dict:
        """Panel holográfico de confirmación de un plan pendiente."""
        with self._lock:
            self._tocar()
            panel = {"id": "confirmar", "kind": "confirmar", "titulo": plan.titulo(),
                     "item_n": None, "payload": plan.a_payload()}
            self.paneles["confirmar"] = panel
            self._emit("confirm", panel=panel)
            return panel

    def resolver_plan(self, plan_id: str, si: bool) -> dict:
        """Confirma o cancela un plan (voz o clic): ejecuta una sola vez y actualiza la pantalla."""
        res = archivos.resolver(plan_id, si)
        plan = res.get("plan")
        if plan is not None:
            self.tras_plan(plan)
        return res

    def tras_plan(self, plan) -> None:
        """Quita el panel de confirmación y, si el plan se ejecutó, anima y relista."""
        with self._lock:
            self._tocar()
            self._quitar_panel("confirmar")
            if plan.estado != "ejecutado" or not self.paneles:
                return
            origenes = {o.origen for o in plan.ops}
            filas = [it.n for it in self.items if it.ruta in origenes]
            ids = [f"v{n}" for n in filas if f"v{n}" in self.paneles]
            self._emit("fx", ids=ids, fx=plan.accion, filas=filas)
            carpeta = plan.carpeta if plan.accion == "crear_carpeta" else str(Path(plan.ops[0].origen).parent)
        if self.retraso_relistado > 0:
            t = threading.Timer(self.retraso_relistado, self.refrescar, [carpeta])
            t.daemon = True
            t.start()
        else:
            self.refrescar(carpeta)

    def refrescar(self, carpeta: str | None = None) -> None:
        """Vuelve a listar la carpeta de la lista que se ve (los números cambian)."""
        with self._lock:
            destino = self.carpeta or carpeta
            if "lista" not in self.paneles or not destino:
                return
            d = self.listador(destino)
            if d.get("ok"):
                self.listar(self.paneles["lista"]["titulo"], d.get("candidatos") or [], carpeta=destino)

    def caducar(self) -> bool:
        """Si ha vencido el tiempo de inactividad, vacía la escena y emite clear."""
        with self._lock:
            if "confirmar" in self.paneles and archivos.pendiente() is None:
                self._quitar_panel("confirmar")
            hay_escena = bool(self.items) or bool(self.paneles)
            if hay_escena and (self.reloj() - self.ultimo_uso > self.ttl):
                _log(f"holo: escena caducada tras {self.reloj() - self.ultimo_uso:.0f}s sin uso (ttl {self.ttl:.0f}s)")
                self.items.clear()
                self.paneles.clear()
                self.seleccionado = None
                self._emit("clear")
                return True
            return False

    def snapshot(self) -> dict:
        """Devuelve una instantánea completa de la escena para nuevos oyentes."""
        with self._lock:
            return {
                "type": "holo",
                "op": "snapshot",
                "items": [asdict(it) for it in self.items],
                "paneles": list(self.paneles.values()),
                "seleccionado": self.seleccionado,
                "panel": None,
                "ids": None,
            }

    def control(self, cmd: str, arg: str) -> dict:
        """Ejecuta un comando recibido por el socket de control de Quickshell.

        Sin lock propio: cada método ya bloquea lo suyo, y `holo-send` puede tardar
        minutos (subida por warp) sin dejar la escena congelada mientras tanto."""
        if cmd == "holo-open":
            try:
                n = int(arg.strip())
                res = self.abrir([n])
                if res.get("ok"):
                    # Item no es JSON: la respuesta del socket de control debe ser serializable
                    res = {**res, "abiertos": [asdict(it) for it in res.get("abiertos", [])]}
                return res
            except ValueError:
                return {"ok": False, "error": f"Número inválido: {arg}"}

        if cmd in ("holo-confirm", "holo-cancel"):
            res = self.resolver_plan(arg.strip(), cmd == "holo-confirm")
            return {"ok": bool(res.get("ok")), "estado": res.get("estado"),
                    "error": res.get("error"), "decir": res.get("decir")}

        if cmd == "holo-select":
            try:
                n = int(arg.strip())
                it = self.seleccionar(n)
                if it is not None:
                    return {"ok": True, "seleccionado": n}
                return {"ok": False, "error": f"Número fuera de rango: {n}"}
            except ValueError:
                return {"ok": False, "error": f"Número inválido: {arg}"}

        if cmd == "holo-close":
            arg_limpio = arg.strip()
            _log(f"holo: control holo-close {arg_limpio!r} (desde la UI)")
            if arg_limpio == "all":
                self.cerrar(todo=True)
                return {"ok": True}
            cuantos = self.cerrar_panel(arg_limpio)
            return {"ok": cuantos > 0}

        if cmd == "holo-send":
            try:
                n = int(arg.strip())
                return self.enviar_por_warp(n)
            except ValueError:
                return {"ok": False, "error": f"Número inválido: {arg}"}

        if cmd == "holo-page":
            partes = arg.strip().split()
            if len(partes) >= 2 and partes[1].isdigit():
                pid = partes[0]
                p = int(partes[1])
                return self.pagina(pid, p)
            return {"ok": False, "error": "Uso: holo-page <pid> <p>"}

        if cmd == "holo-ext":
            arg_limpio = arg.strip()
            if arg_limpio.startswith("v") and arg_limpio[1:].isdigit():
                n = int(arg_limpio[1:])
            elif arg_limpio.isdigit():
                n = int(arg_limpio)
            else:
                return {"ok": False, "error": f"Número inválido: {arg}"}
            item = self.resolver(n)
            if item is None:
                return {"ok": False, "error": f"Archivo {n} no encontrado"}
            return self.abrir_externo(item.ruta)

        return {"ok": False, "error": f"Comando desconocido: {cmd}"}

    def _enviar_por_warp_default(self, n: int) -> dict:
        """Envío predeterminado delegando en la herramienta warp."""
        item = self.resolver(n)
        if item is None:
            return {"ok": False, "error": f"Archivo {n} no encontrado"}
        try:
            from .tools import warp
            res = warp.warp("archivo", ruta=item.ruta)
            if isinstance(res, dict) and res.get("ok"):
                self.marcar_enviado(n)
            return res if isinstance(res, dict) else {"ok": True}
        except Exception as err:
            return {"ok": False, "error": str(err)}

    def _listar_default(self, ruta: str) -> dict:
        """Listado predeterminado de una carpeta delegando en warp."""
        try:
            from .tools import warp
            return warp._warp("listar", ruta)
        except Exception as err:
            return {"ok": False, "error": str(err)}

    def _abrir_externo_default(self, ruta: str) -> dict:
        """Apertura externa predeterminada con xdg-open."""
        try:
            subprocess.Popen(
                ["xdg-open", ruta],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return {"ok": True}
        except Exception as err:
            return {"ok": False, "error": str(err)}


_ESCENA_INSTANCIA: Escena | None = None
_ESCENA_LOCK = threading.Lock()


def escena() -> Escena:
    """Devuelve el singleton de Escena, creándolo de forma perezosa."""
    global _ESCENA_INSTANCIA
    if _ESCENA_INSTANCIA is None:
        with _ESCENA_LOCK:
            if _ESCENA_INSTANCIA is None:
                from .config import bus
                _ESCENA_INSTANCIA = Escena(emit=bus.emit)
    return _ESCENA_INSTANCIA
