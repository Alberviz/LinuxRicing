#!/usr/bin/env python3
"""
spotify-focus-watcher.py: Hyprland socket2 listener that reloads Spicetify theme ONLY when Spotify is focused.
Avoids interrupting background music playback during wallpaper / theme switching.
"""
import os, socket, subprocess, time
from pathlib import Path

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

    while True:
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.connect(sock_path)
            with client.makefile("r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("activewindow>>"):
                        target = line[len("activewindow>>"):].lower()
                        if "spotify" in target and pending_flag.exists():
                            if spicetify_bin.exists():
                                time.sleep(0.15) # smooth transition
                                subprocess.run([str(spicetify_bin), "apply", "-q"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
                                pending_flag.unlink(missing_ok=True)
        except Exception:
            time.sleep(2)

if __name__ == "__main__":
    main()
