#!/usr/bin/env python3
"""
Centro de Configuración de Iluminación Inteligente MCHOSE 8K Base
Gestiona los efectos de Carga y las Alertas de Batería Baja.
"""
import sys
import os
import json

CONFIG_PATH = os.path.expanduser("~/.config/caelestia/mchose-config.json")

DEFAULT_CONFIG = {
    "charging_effect": "theme_breathing",
    "low_battery_effect": "red_breathing",
    "low_battery_threshold": 20
}

def load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r") as f:
                cfg = json.load(f)
                for k, v in DEFAULT_CONFIG.items():
                    cfg.setdefault(k, v)
                return cfg
        except Exception:
            pass
    return dict(DEFAULT_CONFIG)

def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg, f, indent=2)

CHARGING_MODES = {
    "1": ("theme_breathing", "🎨 1. Respiración con color del Tema (Material You)"),
    "theme": ("theme_breathing", "🎨 1. Respiración con color del Tema (Material You)"),
    "2": ("battery_breathing", "🔋 2. Respiración con color según % de Batería (Verde/Ámbar/Rojo)"),
    "battery": ("battery_breathing", "🔋 2. Respiración con color según % de Batería (Verde/Ámbar/Rojo)"),
    "3": ("hardware_battery", "⚡ 3. Modo Batería Oficial del Firmware (Target 0x01)"),
    "hardware": ("hardware_battery", "⚡ 3. Modo Batería Oficial del Firmware (Target 0x01)"),
    "4": ("wave", "🌊 4. Ola Arcoíris giratoria (Wave Target 0x07)"),
    "wave": ("wave", "🌊 4. Ola Arcoíris giratoria (Wave Target 0x07)")
}

LOWBAT_MODES = {
    "1": ("wave", "🌊 1. Ola Arcoíris giratoria (Aviso llamativo para acoplar a la base)"),
    "wave": ("wave", "🌊 1. Ola Arcoíris giratoria (Aviso llamativo para acoplar a la base)"),
    "ola": ("wave", "🌊 1. Ola Arcoíris giratoria (Aviso llamativo para acoplar a la base)"),
    "2": ("red_breathing", "🚨 2. Respiración Roja parpadeante (Alerta visual crítica)"),
    "red": ("red_breathing", "🚨 2. Respiración Roja parpadeante (Alerta visual crítica)"),
    "rojo": ("red_breathing", "🚨 2. Respiración Roja parpadeante (Alerta visual crítica)"),
    "3": ("none", "⚪ 3. Desactivado / Mantener color normal del tema (Sin aviso LED)"),
    "none": ("none", "⚪ 3. Desactivado / Mantener color normal del tema (Sin aviso LED)"),
    "off": ("none", "⚪ 3. Desactivado / Mantener color normal del tema (Sin aviso LED)"),
    "4": ("red_static", "🔴 4. Rojo Fijo constante"),
    "static": ("red_static", "🔴 4. Rojo Fijo constante")
}

def print_status(cfg):
    print("=" * 65)
    print("      🖱️ CONFIGURACIÓN DE ILUMINACIÓN MCHOSE 8K BASE")
    print("=" * 65)
    print(f"🔌 Efecto al CARGAR:         {cfg.get('charging_effect')}")
    print(f"🪫 Alerta de BATERÍA BAJA:   {cfg.get('low_battery_effect')}")
    print(f"📊 Umbral de Batería Baja:   <= {cfg.get('low_battery_threshold')}%")
    print("-" * 65)
    print("Comandos disponibles:")
    print("  • mchose-config charge <1|2|3|4>    -> Cambiar efecto de carga")
    print("  • mchose-config lowbat <1|2|3|4>    -> Cambiar efecto de batería baja")
    print("  • mchose-config threshold <20|30>   -> Cambiar umbral de batería baja")
    print("=" * 65)

def main():
    cfg = load_config()

    if len(sys.argv) == 1:
        print_status(cfg)
        return

    cmd = sys.argv[1].lower().strip()

    if cmd in ["charge", "charging", "carga"]:
        if len(sys.argv) > 2:
            opt = sys.argv[2].lower().strip()
            if opt in CHARGING_MODES:
                key, label = CHARGING_MODES[opt]
                cfg["charging_effect"] = key
                save_config(cfg)
                print(f"✔ Efecto de carga establecido a:\n  {label}")
                os.system("/home/alberviz/.local/bin/mchose-battery --trigger-lighting")
            else:
                print(f"Opción desconocida: '{opt}'. Válidas: 1 (theme), 2 (battery), 3 (hardware), 4 (wave)")
        else:
            print("Uso: mchose-config charge <1|2|3|4|theme|battery|hardware|wave>")

    elif cmd in ["lowbat", "lowbattery", "alerta"]:
        if len(sys.argv) > 2:
            opt = sys.argv[2].lower().strip()
            if opt in LOWBAT_MODES:
                key, label = LOWBAT_MODES[opt]
                cfg["low_battery_effect"] = key
                save_config(cfg)
                print(f"✔ Alerta de batería baja establecida a:\n  {label}")
                os.system("/home/alberviz/.local/bin/mchose-battery --trigger-lighting")
            else:
                print(f"Opción desconocida: '{opt}'. Válidas: 1 (wave), 2 (red), 3 (none), 4 (static)")
        else:
            print("Uso: mchose-config lowbat <1|2|3|4|wave|red|none|static>")

    elif cmd in ["threshold", "umbral"]:
        if len(sys.argv) > 2:
            try:
                val = int(sys.argv[2])
                if 5 <= val <= 50:
                    cfg["low_battery_threshold"] = val
                    save_config(cfg)
                    print(f"✔ Umbral de batería baja establecido en <= {val}%")
                else:
                    print("El umbral debe estar entre 5% y 50%.")
            except ValueError:
                print("Introduce un número entero (ej. 20 o 30).")
        else:
            print("Uso: mchose-config threshold <porcentaje>")

    else:
        print_status(cfg)

if __name__ == "__main__":
    main()
