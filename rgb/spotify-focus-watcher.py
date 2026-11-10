#!/usr/bin/env python3
"""
spotify-focus-watcher.py: Hyprland socket2 listener that:
1. Reloads Spicetify theme ONLY when Spotify is focused (avoids music interruption).
2. Triggers YouTube playlist sync automatically whenever Spotify is opened or focused.
"""
import os, socket, subprocess, threading, time
from pathlib import Path


def trigger_sync(delay_seconds: float = 0.0):
    def _run():
        if delay_seconds > 0:
            time.sleep(delay_seconds)
        subprocess.run(
            ["systemctl", "--user", "start", "--no-block", "spotify-sync-youtube.service"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    threading.Thread(target=_run, daemon=True).start()


def main():
    xdg_runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    hypr_sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")

    sock_path = None
    if hypr_sig:
        candidate = Path(f"{xdg_runtime}/hypr/{hypr_sig}/.socket2.sock")
        if candidate.exists():
            sock_path = str(candidate)

    if not sock_path:
        socks = sorted(list(Path(xdg_runtime).glob("hypr/*/.socket2.sock")), key=os.path.getmtime, reverse=True)
        if socks:
            sock_path = str(socks[0])

    if not sock_path:
        return

    pending_flag = Path.home() / ".cache/spicetify_pending_reload"
    spicetify_bin = Path.home() / ".spicetify/spicetify"
    last_sync_time = 0.0
    SYNC_COOLDOWN = 900.0  # Máximo una sincronización cada 15 min al enfocar

    while True:
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.connect(sock_path)
            with client.makefile("r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    # Evento 1: Se abre una ventana nueva
                    if line.startswith("openwindow>>"):
                        parts = line[len("openwindow>>"):].split(",", 3)
                        wclass = parts[2].lower() if len(parts) > 2 else ""
                        if "spotify" in wclass:
                            now = time.time()
                            if now - last_sync_time > 60:
                                last_sync_time = now
                                trigger_sync(delay_seconds=3.5)

                    # Evento 2: Ventana activa cambia (foco)
                    elif line.startswith("activewindow>>"):
                        target = line[len("activewindow>>"):].lower()
                        if "spotify" in target:
                            # 1) Recarga de Spicetify si estaba pendiente
                            if pending_flag.exists() and spicetify_bin.exists():
                                time.sleep(0.15)  # smooth transition
                                subprocess.run(
                                    [str(spicetify_bin), "apply", "-q"],
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL,
                                    timeout=5,
                                )
                                pending_flag.unlink(missing_ok=True)

                            # 2) Sincronizar playlists si hace más de 15 min
                            now = time.time()
                            if now - last_sync_time > SYNC_COOLDOWN:
                                last_sync_time = now
                                trigger_sync(delay_seconds=0.5)
        except Exception:
            time.sleep(2)


if __name__ == "__main__":
    main()
