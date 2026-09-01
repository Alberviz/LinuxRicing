"""Bus de eventos de Aurora.

Un socket Unix (`SOCK_STREAM`) que acepta varios lectores a la vez y les emite
eventos como JSON, uno por línea. Lo consume el overlay de Quickshell; si no hay
nadie escuchando, `emit()` es casi un no-op.

Eventos que se emiten (ver `aurorad.py`):

    {"type":"state","value":"idle|listening|thinking|speaking","mode":"centro|barra"}
    {"type":"amplitude","value":0.0-1.0}
    {"type":"transcript","value":"lo que dijo Alberto"}
    {"type":"result","actions":[{"icon":"volume_up","text":"Subir volumen"}, ...]}

Al conectarse, un lector nuevo recibe de inmediato el último `state` conocido
para poder pintar la ventana correcta sin esperar al siguiente ciclo.
"""
from __future__ import annotations

import json
import os
import socket
import threading


class EventBus:
    def __init__(self, path: str) -> None:
        self.path = os.path.expandvars(path)
        self._clients: list[socket.socket] = []
        self._lock = threading.Lock()
        self._last_state: dict | None = None
        self._srv: socket.socket | None = None

    def start(self) -> None:
        if os.path.exists(self.path):
            os.unlink(self.path)
        self._srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._srv.bind(self.path)
        self._srv.listen(8)
        threading.Thread(target=self._accept_loop, daemon=True).start()

    def _accept_loop(self) -> None:
        assert self._srv is not None
        while True:
            try:
                conn, _ = self._srv.accept()
            except OSError:
                break
            conn.setblocking(True)
            with self._lock:
                self._clients.append(conn)
                snapshot = self._last_state
            if snapshot is not None:
                self._send(conn, snapshot)

    @staticmethod
    def _send(conn: socket.socket, obj: dict) -> bool:
        try:
            conn.sendall((json.dumps(obj, ensure_ascii=False) + "\n").encode())
            return True
        except OSError:
            return False

    def emit(self, **obj) -> None:
        if obj.get("type") == "state":
            self._last_state = obj
        with self._lock:
            dead = [c for c in self._clients if not self._send(c, obj)]
            for c in dead:
                self._clients.remove(c)
                c.close()

    def close(self) -> None:
        if self._srv is not None:
            self._srv.close()
        with self._lock:
            for c in self._clients:
                c.close()
            self._clients.clear()
        if os.path.exists(self.path):
            os.unlink(self.path)
