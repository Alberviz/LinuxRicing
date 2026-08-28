#!/usr/bin/env bash
# ==============================================================================
#  🛸 ALBERVIZ LINUX RICING - MODULAR MULTI-DEVICE INSTALLER
#  Compatible con Arch Linux, Calamares, EndeavourOS, Caelestia & Hyprland
# ==============================================================================
#
#  Enlaces repo -> sistema (son COPIAS, no symlinks; reinstalar tras cada cambio):
#    configs/hypr/*                  -> ~/.config/hypr/
#    configs/quickshell/caelestia/*  -> ~/.config/quickshell/caelestia/
#    configs/caelestia/cli.json      -> ~/.config/caelestia/cli.json   (hook de tema)
#    configs/caelestia/shell.json    -> ~/.config/caelestia/shell.json (semilla)
#    configs/caelestia/rgb-config.json -> ~/.config/caelestia/         (semilla)
#    configs/spicetify/Themes/*      -> ~/.config/spicetify/Themes/
#    widgets/Background.qml          -> ~/.config/quickshell/caelestia/modules/background/
#    widgets/{gtasks,desktop-deck-helper} -> ~/.local/bin/
#    rgb/{sync-rgb,argb-wave}.py     -> ~/.config/caelestia/
#    rgb/{akko-rgb,battery-lighting,magichome-control,mchose-battery,
#         mchose-lighting,rgb-notify-flash} -> ~/.local/bin/
#    systemd/*.service              -> ~/.config/systemd/user/
# ==============================================================================

set -e

# Colores y estilos
BOLD='\033[1m'
PRIMARY='\033[38;5;216m'
SECONDARY='\033[38;5;152m'
SUCCESS='\033[38;5;114m'
WARNING='\033[38;5;221m'
ERROR='\033[38;5;203m'
RESET='\033[0m'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config/ricing_backup_$(date +%Y%m%d_%H%M%S)"

echo -e "${PRIMARY}${BOLD}"
cat << "BANNER"
  _      _____ _   _ _   ___  __  ____  _____ _____ _____ _   _  _____ 
 | |    |_   _| \ | | | | \ \/ / |  _ \|_   _/ ____|_   _| \ | |/ ____|
 | |      | | |  \| | | | |\  /  | |_) | | || |      | | |  \| | |  __ 
 | |      | | | . ` | | | |/  \  |  _ <  | || |      | | | . ` | | |_ |
 | |____ _| |_| |\  | |_| / /\ \ | |_) |_| || |____ _| |_| |\  | |__| |
 |______|_____|_| \_|\___/_/  \_\|____/|_____\_____|_____|_| \_|\_____|
BANNER
echo -e "${RESET}"
echo -e "${SECONDARY}Instalador Modular para Sobremesa & Portátiles (Arch / Hyprland / Caelestia)${RESET}"
echo -e "Directorio de origen: ${BOLD}$BASE_DIR${RESET}\n"

# Detección de chasis (Laptop vs Desktop)
IS_LAPTOP=false
if [ -d "/sys/class/power_supply" ] && ls /sys/class/power_supply/BAT* 1>/dev/null 2>&1; then
    IS_LAPTOP=true
    echo -e "${SUCCESS}ℹ Dispositivo detectado: ${BOLD}PORTÁTIL${RESET} (Batería interna encontrada)"
else
    echo -e "${SUCCESS}ℹ Dispositivo detectado: ${BOLD}SOBREMESA / WORKSTATION${RESET}"
fi

# Selección de componentes interactiva
SELECTED_HYPR=true
SELECTED_CAELESTIA=true
SELECTED_WIDGETS=true
SELECTED_GTASKS=true
SELECTED_SPICETIFY=true
SELECTED_RGB=true
SELECTED_LAPTOP_OPTS=false

if [ "$IS_LAPTOP" = true ]; then
    SELECTED_RGB=false
    SELECTED_LAPTOP_OPTS=true
fi

# Menú interactivo si zenity o whiptail están disponibles
if command -v zenity >/dev/null 2>&1 && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
    CHOICES=$(zenity --list --checklist \
        --title="Instalador de Rice - Alberviz" \
        --column="Instalar" --column="ID" --column="Componente" \
        TRUE "HYPR" "Hyprland Configs & Atajos (Super+W, gestos)" \
        TRUE "CAEL" "Caelestia Quickshell Shell & Material You M3" \
        TRUE "WIDG" "Deck de Widgets (Tareas, Clima, HW, Pomodoro)" \
        TRUE "GTASKS" "Google Tasks CLI & Integración de Escritorio" \
        TRUE "SPICE" "Spotify / Spicetify Auto-Sync con Material You" \
        $([ "$SELECTED_RGB" = true ] && echo "TRUE" || echo "FALSE") "RGB" "Control Hardware RGB (OpenRGB, MCHOSE, MagicHome, Akko)" \
        $([ "$SELECTED_LAPTOP_OPTS" = true ] && echo "TRUE" || echo "FALSE") "LAPTOP" "Optimizaciones de Portátil (Ahorro energía, gestos)" \
        --width=650 --height=400 --separator=":")

    if [ -n "$CHOICES" ]; then
        SELECTED_HYPR=false; SELECTED_CAELESTIA=false; SELECTED_WIDGETS=false
        SELECTED_GTASKS=false; SELECTED_SPICETIFY=false; SELECTED_RGB=false; SELECTED_LAPTOP_OPTS=false
        [[ "$CHOICES" =~ "HYPR" ]] && SELECTED_HYPR=true
        [[ "$CHOICES" =~ "CAEL" ]] && SELECTED_CAELESTIA=true
        [[ "$CHOICES" =~ "WIDG" ]] && SELECTED_WIDGETS=true
        [[ "$CHOICES" =~ "GTASKS" ]] && SELECTED_GTASKS=true
        [[ "$CHOICES" =~ "SPICE" ]] && SELECTED_SPICETIFY=true
        [[ "$CHOICES" =~ "RGB" ]] && SELECTED_RGB=true
        [[ "$CHOICES" =~ "LAPTOP" ]] && SELECTED_LAPTOP_OPTS=true
    fi
fi

echo -e "\n${BOLD}Resumen de instalación:${RESET}"
echo -e " • Hyprland Configs: $([ "$SELECTED_HYPR" = true ] && echo -e "${SUCCESS}SI${RESET}" || echo -e "${ERROR}NO${RESET}")"
echo -e " • Caelestia Shell:  $([ "$SELECTED_CAELESTIA" = true ] && echo -e "${SUCCESS}SI${RESET}" || echo -e "${ERROR}NO${RESET}")"
echo -e " • Desktop Widgets:  $([ "$SELECTED_WIDGETS" = true ] && echo -e "${SUCCESS}SI${RESET}" || echo -e "${ERROR}NO${RESET}")"
echo -e " • Google Tasks:     $([ "$SELECTED_GTASKS" = true ] && echo -e "${SUCCESS}SI${RESET}" || echo -e "${ERROR}NO${RESET}")"
echo -e " • Spicetify Sync:   $([ "$SELECTED_SPICETIFY" = true ] && echo -e "${SUCCESS}SI${RESET}" || echo -e "${ERROR}NO${RESET}")"
echo -e " • RGB Hardware:     $([ "$SELECTED_RGB" = true ] && echo -e "${SUCCESS}SI${RESET}" || echo -e "${ERROR}NO${RESET}")"
echo -e " • Laptop Opts:      $([ "$SELECTED_LAPTOP_OPTS" = true ] && echo -e "${SUCCESS}SI${RESET}" || echo -e "${ERROR}NO${RESET}")\n"

# Crear carpetas base
mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.cache"

# 1. Instalar Hyprland Configs
if [ "$SELECTED_HYPR" = true ]; then
    echo -e "${PRIMARY}➔ Instalando configuraciones de Hyprland...${RESET}"
    mkdir -p "$HOME/.config/hypr"
    if [ -d "$BASE_DIR/configs/hypr" ]; then
        # Árbol completo: hyprland.lua, config/, hyprland/, scheme/, utils/, xdph.conf
        cp -ru "$BASE_DIR/configs/hypr/"* "$HOME/.config/hypr/"
        echo -e "  ${SUCCESS}✔ Configs de Hyprland instaladas (binds Super+W, scheme, utils, xdph)${RESET}"
    fi
fi

# 2. Instalar Caelestia Quickshell
if [ "$SELECTED_CAELESTIA" = true ]; then
    echo -e "${PRIMARY}➔ Desplegando Caelestia Quickshell Shell...${RESET}"
    mkdir -p "$HOME/.config/quickshell/caelestia" "$HOME/.config/caelestia"
    if [ -d "$BASE_DIR/configs/quickshell/caelestia" ]; then
        cp -ru "$BASE_DIR/configs/quickshell/caelestia/"* "$HOME/.config/quickshell/caelestia/"
        echo -e "  ${SUCCESS}✔ Caelestia Shell y servicios MPRIS instalados${RESET}"
    fi
    # shell.json: semilla de configuración del shell (no pisar la del usuario)
    if [ -f "$BASE_DIR/configs/caelestia/shell.json" ] && [ ! -f "$HOME/.config/caelestia/shell.json" ]; then
        cp "$BASE_DIR/configs/caelestia/shell.json" "$HOME/.config/caelestia/shell.json"
    fi
fi

# 3. Instalar Widgets de Escritorio
if [ "$SELECTED_WIDGETS" = true ]; then
    echo -e "${PRIMARY}➔ Instalando Desktop Widgets (Background.qml y Helper)...${RESET}"
    mkdir -p "$HOME/.config/quickshell/caelestia/modules/background"
    if [ -f "$BASE_DIR/widgets/Background.qml" ]; then
        cp -u "$BASE_DIR/widgets/Background.qml" "$HOME/.config/quickshell/caelestia/modules/background/Background.qml"
        echo -e "  ${SUCCESS}✔ Background.qml con Deck interactivo desplegado${RESET}"
    fi
    if [ -f "$BASE_DIR/widgets/desktop-deck-helper" ]; then
        cp -u "$BASE_DIR/widgets/desktop-deck-helper" "$HOME/.local/bin/desktop-deck-helper"
        chmod +x "$HOME/.local/bin/desktop-deck-helper"
        echo -e "  ${SUCCESS}✔ Helper de Clima y Hardware instalado en ~/.local/bin${RESET}"
    fi
fi

# 4. Instalar Google Tasks CLI
if [ "$SELECTED_GTASKS" = true ]; then
    echo -e "${PRIMARY}➔ Instalando Google Tasks CLI...${RESET}"
    if [ -f "$BASE_DIR/widgets/gtasks" ]; then
        cp -u "$BASE_DIR/widgets/gtasks" "$HOME/.local/bin/gtasks"
        chmod +x "$HOME/.local/bin/gtasks"
        echo -e "  ${SUCCESS}✔ gtasks instalado en ~/.local/bin${RESET}"
    fi
fi

# 5. Instalar Spicetify Dynamic Material You Theme
if [ "$SELECTED_SPICETIFY" = true ]; then
    echo -e "${PRIMARY}➔ Configurando Spicetify y tema Caelestia...${RESET}"
    mkdir -p "$HOME/.config/spicetify/Themes/caelestia"
    if [ -d "$BASE_DIR/configs/spicetify/Themes/caelestia" ]; then
        cp -ru "$BASE_DIR/configs/spicetify/Themes/caelestia/"* "$HOME/.config/spicetify/Themes/caelestia/"
    fi
    if command -v spicetify >/dev/null 2>&1; then
        spicetify config current_theme caelestia || true
        spicetify apply -q || true
        echo -e "  ${SUCCESS}✔ Spicetify vinculado al tema caelestia${RESET}"
    fi
fi

# 6. Instalar RGB Hardware Control (Solo si está seleccionado)
if [ "$SELECTED_RGB" = true ]; then
    echo -e "${PRIMARY}➔ Instalando controladores de hardware RGB y daemon...${RESET}"
    mkdir -p "$HOME/.config/caelestia"

    # 6a. Scripts que corren desde ~/.config/caelestia (los invoca el hook de tema)
    for f in sync-rgb.py argb-wave.py; do
        if [ -f "$BASE_DIR/rgb/$f" ]; then
            cp -u "$BASE_DIR/rgb/$f" "$HOME/.config/caelestia/$f"
            chmod +x "$HOME/.config/caelestia/$f"
        fi
    done

    # 6b. Semillas de configuración de Caelestia (no pisar las del usuario)
    if [ -f "$BASE_DIR/configs/caelestia/cli.json" ]; then
        cp -u "$BASE_DIR/configs/caelestia/cli.json" "$HOME/.config/caelestia/cli.json"
    fi
    for seed in rgb-config.json; do
        if [ -f "$BASE_DIR/configs/caelestia/$seed" ] && [ ! -f "$HOME/.config/caelestia/$seed" ]; then
            cp "$BASE_DIR/configs/caelestia/$seed" "$HOME/.config/caelestia/$seed"
        fi
    done

    # 6c. Binarios CLI en ~/.local/bin
    for bin in akko-rgb battery-lighting magichome-control mchose-battery \
               mchose-lighting rgb-notify-flash; do
        if [ -f "$BASE_DIR/rgb/$bin" ]; then
            cp -u "$BASE_DIR/rgb/$bin" "$HOME/.local/bin/$bin"
            chmod +x "$HOME/.local/bin/$bin"
        fi
    done

    # 6d. Unidades systemd de usuario
    if [ -d "$BASE_DIR/systemd" ]; then
        mkdir -p "$HOME/.config/systemd/user"
        cp -u "$BASE_DIR/systemd/"*.service "$HOME/.config/systemd/user/" 2>/dev/null || true
        systemctl --user daemon-reload || true
        # openrgb + battery-lighting siempre; argb-wave solo si su script existe (rama feature/argb-wave)
        UNITS="openrgb.service battery-lighting.service"
        [ -f "$BASE_DIR/rgb/argb-wave.py" ] && UNITS="$UNITS argb-wave.service"
        systemctl --user enable --now $UNITS 2>/dev/null || true
    fi

    echo -e "  ${SUCCESS}✔ Controladores RGB y batería instalados${RESET}"
else
    echo -e "${WARNING}ℹ Componentes RGB omitidos para este dispositivo.${RESET}"
fi

# Recargar Caelestia si está en ejecución
if pgrep -f "quickshell" >/dev/null 2>&1; then
    echo -e "\n${PRIMARY}➔ Recargando Caelestia Shell...${RESET}"
    caelestia shell -k || true
    sleep 1
    caelestia shell -d || true
fi

echo -e "\n${SUCCESS}${BOLD}✨ ¡Instalación y sincronización completada con éxito!${RESET}"
