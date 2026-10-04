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
#    configs/quickshell/caelestia/modules/background/* -> ~/.config/.../modules/background/
#    widgets/{caelestia-server-mode,volver-escritorio} -> ~/.local/bin/  (modo servidor)
#    configs/system/caelestia-server-mode-root  -> /usr/local/bin/        (sudo, helper acotado)
#    configs/system/caelestia-server-mode.sudoers -> /etc/sudoers.d/caelestia-server-mode (0440)
#    configs/system/caelestia-power-root{,.sudoers} -> /usr/local/bin/ + /etc/sudoers.d/caelestia-power-root (ahorro)
#    widgets/{gtasks,desktop-deck-helper,display-selector,magichome-control,lenovo-battery-control} -> ~/.local/bin/
#    configs/applications/lenovo-battery-control.desktop -> ~/.local/share/applications/
#    configs/udev/99-lenovo-conservation.rules -> /etc/udev/rules.d/  (manual, con sudo)
#    rgb/{sync-rgb,argb-wave}.py     -> ~/.config/caelestia/
#    rgb/sounds/*                    -> ~/.config/caelestia/sounds/  (paletas de notificación)
#    rgb/{agent-notify,akko-rgb,battery-lighting,magichome-control,mchose-battery,
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
    if [ -d "$BASE_DIR/configs/quickshell/caelestia/modules/background" ]; then
        cp -ru "$BASE_DIR/configs/quickshell/caelestia/modules/background/"* "$HOME/.config/quickshell/caelestia/modules/background/"
        echo -e "  ${SUCCESS}✔ Módulo Background (Deck interactivo, modularizado) desplegado${RESET}"
    fi
    if [ -f "$BASE_DIR/widgets/desktop-deck-helper" ]; then
        cp -u "$BASE_DIR/widgets/desktop-deck-helper" "$HOME/.local/bin/desktop-deck-helper"
        chmod +x "$HOME/.local/bin/desktop-deck-helper"
        echo -e "  ${SUCCESS}✔ Helper de Clima y Hardware instalado en ~/.local/bin${RESET}"
    fi
    if [ -f "$BASE_DIR/widgets/display-selector" ]; then
        cp -u "$BASE_DIR/widgets/display-selector" "$HOME/.local/bin/display-selector"
        chmod +x "$HOME/.local/bin/display-selector"
        echo -e "  ${SUCCESS}✔ Selector de pantallas (Win+P) instalado en ~/.local/bin${RESET}"
    fi

    # 3b. Modo servidor: scripts de usuario (el botón "Server mode" de Caelestia
    #     invoca `caelestia-server-mode on`; `volver-escritorio` es la vuelta desde tty)
    for bin in caelestia-server-mode volver-escritorio; do
        if [ -f "$BASE_DIR/widgets/$bin" ]; then
            cp -u "$BASE_DIR/widgets/$bin" "$HOME/.local/bin/$bin"
            chmod +x "$HOME/.local/bin/$bin"
        fi
    done
    echo -e "  ${SUCCESS}✔ Scripts de modo servidor instalados en ~/.local/bin${RESET}"

    # 3c. Modo servidor: helper privilegiado + regla sudoers acotada.
    #     El helper solo acepta 4 verbos fijos (console/desktop/issue-on/issue-off).
    SM_ROOT_SRC="$BASE_DIR/configs/system/caelestia-server-mode-root"
    SM_SUDOERS_SRC="$BASE_DIR/configs/system/caelestia-server-mode.sudoers"
    if [ -f "$SM_ROOT_SRC" ] && [ -f "$SM_SUDOERS_SRC" ]; then
        echo -e "${PRIMARY}➔ Instalando helper privilegiado del modo servidor (pide sudo)...${RESET}"
        if sudo install -m 0755 -o root -g root "$SM_ROOT_SRC" /usr/local/bin/caelestia-server-mode-root; then
            SM_TMP="$(mktemp)"
            install -m 0440 "$SM_SUDOERS_SRC" "$SM_TMP"
            if visudo -cf "$SM_TMP" >/dev/null 2>&1; then
                sudo install -m 0440 -o root -g root "$SM_TMP" /etc/sudoers.d/caelestia-server-mode
                echo -e "  ${SUCCESS}✔ /usr/local/bin/caelestia-server-mode-root + /etc/sudoers.d/caelestia-server-mode${RESET}"
            else
                echo -e "  ${ERROR}✖ La regla sudoers no valida con visudo; se omite. Revisa $SM_SUDOERS_SRC${RESET}"
            fi
            rm -f "$SM_TMP"
        else
            echo -e "  ${WARNING}ℹ No se pudo instalar el helper (sin sudo). El botón de modo servidor no funcionará hasta hacerlo.${RESET}"
        fi
    fi

    # 3d. Ahorro extremo de energía: helper privilegiado (no_turbo, WiFi/audio PM, teclado).
    PW_ROOT_SRC="$BASE_DIR/configs/system/caelestia-power-root"
    if [ -f "$PW_ROOT_SRC" ]; then
        echo -e "${PRIMARY}➔ Instalando helper privilegiado de ahorro de energía (pide sudo)...${RESET}"
        if sudo install -m 0755 -o root -g root "$PW_ROOT_SRC" /usr/local/bin/caelestia-power-root; then
            echo -e "  ${SUCCESS}✔ /usr/local/bin/caelestia-power-root${RESET}"
            PW_SUDOERS_SRC="$BASE_DIR/configs/system/caelestia-power-root.sudoers"
            if [ -f "$PW_SUDOERS_SRC" ]; then
                PW_TMP="$(mktemp)"
                install -m 0440 "$PW_SUDOERS_SRC" "$PW_TMP"
                if visudo -cf "$PW_TMP" >/dev/null 2>&1; then
                    sudo install -m 0440 -o root -g root "$PW_TMP" /etc/sudoers.d/caelestia-power-root
                    echo -e "  ${SUCCESS}✔ /etc/sudoers.d/caelestia-power-root${RESET}"
                else
                    echo -e "  ${ERROR}✖ La regla sudoers no valida con visudo; se omite. Revisa $PW_SUDOERS_SRC${RESET}"
                fi
                rm -f "$PW_TMP"
            fi
        else
            echo -e "  ${WARNING}ℹ No se pudo instalar caelestia-power-root (sin sudo). El ahorro extremo no aplicará tweaks de hardware.${RESET}"
        fi
    fi

    # Control de batería Lenovo (Modo Conservación 80% + "Cargar al 100%").
    # El popout de batería de Caelestia y el lanzador GTK llaman a este binario.
    if [ -f "$BASE_DIR/widgets/lenovo-battery-control" ]; then
        cp -u "$BASE_DIR/widgets/lenovo-battery-control" "$HOME/.local/bin/lenovo-battery-control"
        chmod +x "$HOME/.local/bin/lenovo-battery-control"
        mkdir -p "$HOME/.local/share/applications"
        cp -u "$BASE_DIR/configs/applications/lenovo-battery-control.desktop" "$HOME/.local/share/applications/lenovo-battery-control.desktop"
        echo -e "  ${SUCCESS}✔ Control de batería Lenovo instalado en ~/.local/bin${RESET}"

        # La regla udev hace escribible conservation_mode sin root. Necesita sudo,
        # así que no se aplica sola: se copia si falta y se recargan las reglas.
        UDEV_SRC="$BASE_DIR/configs/udev/99-lenovo-conservation.rules"
        UDEV_DST="/etc/udev/rules.d/99-lenovo-conservation.rules"
        if [ -f "$UDEV_SRC" ] && [ ! -f "$UDEV_DST" ]; then
            if [ -e /sys/bus/platform/drivers/ideapad_acpi ]; then
                echo -e "  ${WARNING}ℹ Falta la regla udev de conservación. Para instalarla:${RESET}"
                echo -e "      ${WARNING}sudo cp '$UDEV_SRC' '$UDEV_DST' && sudo udevadm control --reload && sudo udevadm trigger${RESET}"
            fi
        fi
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

    # 6b-bis. Paletas de sonido para las notificaciones de agentes
    if [ -d "$BASE_DIR/rgb/sounds" ]; then
        mkdir -p "$HOME/.config/caelestia/sounds"
        cp -ru "$BASE_DIR/rgb/sounds/"* "$HOME/.config/caelestia/sounds/"
    fi

    # 6c. Binarios CLI en ~/.local/bin
    for bin in agent-notify akko-rgb battery-lighting magichome-control mchose-battery \
               mchose-lighting rgb-notify-flash; do
        if [ -f "$BASE_DIR/rgb/$bin" ]; then
            cp -u "$BASE_DIR/rgb/$bin" "$HOME/.local/bin/$bin"
            chmod +x "$HOME/.local/bin/$bin"
        fi
    done

    # 6d. Unidades systemd de usuario
    if [ -d "$BASE_DIR/systemd" ]; then
        mkdir -p "$HOME/.config/systemd/user"
        # Retira unidades legacy: mchose-battery.{timer,service} lanzaban
        # `mchose-battery --notify`, flag que ya no existe (la telemetría y las
        # notificaciones viven ahora en battery-lighting). El servicio quedaba
        # en fallo perpetuo y su caché rancia confundía al widget de periféricos.
        for legacy in mchose-battery.timer mchose-battery.service; do
            if [ -f "$HOME/.config/systemd/user/$legacy" ] || \
               systemctl --user list-unit-files "$legacy" >/dev/null 2>&1; then
                systemctl --user disable --now "$legacy" 2>/dev/null || true
                rm -f "$HOME/.config/systemd/user/$legacy"
            fi
        done
        cp -u "$BASE_DIR/systemd/"*.service "$HOME/.config/systemd/user/" 2>/dev/null || true
        systemctl --user daemon-reload || true
        # openrgb + battery-lighting siempre; argb-wave solo si su script existe (rama feature/argb-wave)
        UNITS="openrgb.service battery-lighting.service"
        [ -f "$BASE_DIR/rgb/argb-wave.py" ] && UNITS="$UNITS argb-wave.service"
        systemctl --user enable --now $UNITS 2>/dev/null || true
    fi

    # 6e. Semilla del estilo del marcador de agentes (no pisar la del usuario)
    if [ ! -f "$HOME/.config/caelestia/agents-config.json" ]; then
        printf '{\n  "runningStyle": "blink",\n  "unseenMarker": "badge"\n}\n' \
            > "$HOME/.config/caelestia/agents-config.json"
    fi

    # 6f. Hooks de Claude Code para las notificaciones de agentes.
    #     Fusiona configs/claude/agent-hooks.json en ~/.claude/settings.json de forma
    #     idempotente (solo añade UserPromptSubmit/Stop si no están ya). Sin jq -> aviso.
    HOOKS_SRC="$BASE_DIR/configs/claude/agent-hooks.json"
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"
    if [ -f "$HOOKS_SRC" ]; then
        if command -v jq >/dev/null 2>&1; then
            mkdir -p "$HOME/.claude"
            [ -f "$CLAUDE_SETTINGS" ] || echo '{}' > "$CLAUDE_SETTINGS"
            if jq -e '.hooks.Stop[]?.hooks[]?.command | select(test("agent-notify"))' \
                 "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
                echo -e "  ${SUCCESS}✔ Hooks de agent-notify ya presentes en ~/.claude/settings.json${RESET}"
            else
                cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%s)"
                tmp_settings="$(mktemp)"
                jq -s '.[0] * .[1]' "$CLAUDE_SETTINGS" "$HOOKS_SRC" > "$tmp_settings" \
                    && mv "$tmp_settings" "$CLAUDE_SETTINGS" \
                    && echo -e "  ${SUCCESS}✔ Hooks de agent-notify añadidos a ~/.claude/settings.json${RESET}" \
                    || echo -e "  ${WARNING}ℹ No se pudieron fusionar los hooks; hazlo a mano desde $HOOKS_SRC${RESET}"
            fi
        else
            echo -e "  ${WARNING}ℹ 'jq' no encontrado. Para el pulso 'en curso' de Claude Code, fusiona"
            echo -e "     $HOOKS_SRC en ~/.claude/settings.json (claves UserPromptSubmit y Stop).${RESET}"
        fi
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
