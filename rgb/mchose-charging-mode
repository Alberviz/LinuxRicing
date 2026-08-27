#!/usr/bin/env python3
"""
Selector de Efecto de Carga para la Base MCHOSE 8K
Opciones:
  1: theme_breathing   - Respiración suave con el color del tema/wallpaper (Material You)
  2: battery_breathing - Respiración con el color según el nivel de batería (Verde/Ámbar/Rojo)
  3: hardware_battery  - Modo oficial de batería del firmware de la base (Target 0x01)
  4: wave              - Ola Arcoíris giratoria (Target 0x07)
"""
import sys
import os
import json

CONFIG_PATH = os.path.expanduser("~/.config/caelestia/mchose-config.json")

def load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {"charging_effect": "theme_breathing"}

def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg, f, indent=2)

MODES = {
    "1": ("theme_breathing", "🎨 1. Respiración con color del Tema (Material You)"),
    "theme": ("theme_breathing", "🎨 1. Respiración con color del Tema (Material You)"),
    "tema": ("theme_breathing", "🎨 1. Respiración con color del Tema (Material You)"),
    "2": ("battery_breathing", "🔋 2. Respiración con color según % de Batería (Verde/Ámbar/Rojo)"),
    "battery": ("battery_breathing", "🔋 2. Respiración con color según % de Batería (Verde/Ámbar/Rojo)"),
    "bateria": ("battery_breathing", "🔋 2. Respiración con color según % de Batería (Verde/Ámbar/Rojo)"),
    "3": ("hardware_battery", "⚡ 3. Modo Batería Oficial del Firmware (Target 0x01)"),
    "hardware": ("hardware_battery", "⚡ 3. Modo Batería Oficial del Firmware (Target 0x01)"),
    "oficial": ("hardware_battery", "⚡ 3. Modo Batería Oficial del Firmware (Target 0x01)"),
    "4": ("wave", "🌊 4. Ola Arcoíris giratoria (Wave Target 0x07)"),
    "wave": ("wave", "🌊 4. Ola Arcoíris giratoria (Wave Target 0x07)"),
    "ola": ("wave", "🌊 4. Ola Arcoíris giratoria (Wave Target 0x07)")
}

if len(sys.argv) > 1:
    arg = sys.argv[1].lower().strip()
    if arg in MODES:
        key, label = MODES[arg]
        cfg = load_config()
        cfg["charging_effect"] = key
        save_config(cfg)
        print(f"✔ Efecto de carga configurado a:\n  {label}")
        # Aplicar inmediatamente si el ratón está cargando
        os.system("/home/alberviz/.local/bin/mchose-battery --trigger-lighting")
    else:
        print(f"Opción desconocida: '{arg}'. Opciones válidas: theme, battery, hardware, wave (o 1, 2, 3, 4)")
else:
    cfg = load_config()
    current = cfg.get("charging_effect", "theme_breathing")
    print("=" * 60)
    print("      🔌 SELECTOR DE EFECTO DE CARGA MCHOSE 8K")
    print("=" * 60)
    print(f"Efecto actualmente activo: {current}\n")
    print("Opciones disponibles:")
    print("  [1] theme    -> Respiración suave con el color del Tema (Material You)")
    print("  [2] battery  -> Respiración con color dinámico de Batería (Verde/Ámbar/Rojo)")
    print("  [3] hardware -> Modo Batería Oficial del Firmware de la base")
    print("  [4] wave     -> Ola Arcoíris giratoria (Wave)")
    print("\nPara cambiarlo ejecuta por ejemplo: mchose-charging-mode 1  (o 'theme', 'battery', etc.)")
