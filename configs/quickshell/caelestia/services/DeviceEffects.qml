pragma Singleton

import QtQuick
import Quickshell

// Descriptor de las animaciones de firmware disponibles por dispositivo RGB, y
// helpers para el objeto "efecto" {animation, colour:{source,hex}, speed,
// direction}. Espejo de DEVICE_EFFECTS / AKKO_ANIM_BYTE en rgb/battery-lighting
// y rgb/sync-rgb.py — mantener en sync. Ver docs/AKKO_EFFECTS_MODEL_HANDOFF.md.
Singleton {
    id: root

    // animación -> etiqueta (todas las que pasaron la prueba de hardware)
    readonly property var animationLabels: ({
            "off": qsTr("Apagado"),
            "solid": qsTr("Sólido"),
            "breathing": qsTr("Respiración"),
            "neon": qsTr("Neón (arcoíris)"),
            "wave": qsTr("Ola"),
            "sine_wave": qsTr("Ola radial"),
            "kaleidoscope": qsTr("Caleidoscopio"),
            "line_wave": qsTr("Ola lineal"),
            "snake": qsTr("Serpiente"),
            "ripple": qsTr("Onda al pulsar"),
            "press_action": qsTr("Reactivo al pulsar"),
            "converge": qsTr("Convergencia"),
            "laser": qsTr("Láser"),
            "circle_wave": qsTr("Ola circular"),
            "dazzing": qsTr("Destello"),
            "meteor": qsTr("Meteoro"),
            "train": qsTr("Tren"),
            "fireworks": qsTr("Fuegos artificiales"),
            "raindrop": qsTr("Gotas"),
            "hardware_battery": qsTr("Batería del firmware")
        })

    readonly property var colourSourceLabels: ({
            "theme": qsTr("Color del tema"),
            "fixed": qsTr("Color fijo"),
            "battery": qsTr("Nivel de batería")
        })

    readonly property var directionLabels: ({
            "right": qsTr("→"),
            "left": qsTr("←"),
            "down": qsTr("↓"),
            "up": qsTr("↑")
        })
    readonly property var directions: ["right", "left", "down", "up"]

    // Descriptor por dispositivo. `animations` es una lista (orden de la UI) o,
    // para dispositivos con zonas, un objeto zona -> lista.
    readonly property var devices: ({
            "akko_keyboard": {
                "zones": ["keys", "sidestrip"],
                "animations": {
                    "keys": ["off", "solid", "breathing", "neon", "wave", "sine_wave", "kaleidoscope", "line_wave", "snake", "ripple", "press_action", "converge", "laser", "circle_wave", "dazzing", "meteor", "train", "fireworks", "raindrop"],
                    "sidestrip": ["off", "solid", "breathing", "neon", "wave", "snake"]
                },
                "colourSources": ["theme", "fixed", "battery"],
                "hasSpeed": true,
                "directional": ["wave"]
            },
            "mchose_base": {
                "zones": [],
                "animations": ["off", "solid", "breathing", "wave", "hardware_battery"],
                "colourSources": ["theme", "fixed", "battery"],
                "hasSpeed": false,
                "directional": []
            }
        })

    function animationsFor(device: string, zone: string): var {
        const d = root.devices[device];
        if (!d)
            return [];
        if (Array.isArray(d.animations))
            return d.animations;
        return d.animations[zone === "sidestrip" ? "sidestrip" : "keys"] ?? [];
    }

    function isDirectional(device: string, animation: string): bool {
        return (root.devices[device]?.directional ?? []).includes(animation);
    }

    function hasSpeed(device: string): bool {
        return !!(root.devices[device]?.hasSpeed);
    }

    function animationLabel(a: string): string {
        return root.animationLabels[a] ?? a;
    }

    readonly property var defaultEffect: ({
            "animation": "solid",
            "colour": { "source": "theme", "hex": "d8bde7" },
            "speed": 3,
            "direction": "right"
        })

    // Normaliza un efecto (acepta string antiguo o dict parcial) a la forma completa.
    readonly property var _aliases: ({
            "theme": { "animation": "solid", "colour": { "source": "theme" } },
            "fixed": { "animation": "solid", "colour": { "source": "fixed" } },
            "battery_color": { "animation": "solid", "colour": { "source": "battery" } },
            "breathing": { "animation": "breathing", "colour": { "source": "theme" } },
            "breathing_battery": { "animation": "breathing", "colour": { "source": "battery" } },
            "theme_breathing": { "animation": "breathing", "colour": { "source": "theme" } },
            "wave": { "animation": "wave", "colour": { "source": "theme" } },
            "wave_battery": { "animation": "wave", "colour": { "source": "battery" } },
            "stream": { "animation": "snake", "colour": { "source": "battery" } },
            "stream_battery": { "animation": "snake", "colour": { "source": "battery" } },
            "reactive_press": { "animation": "press_action", "colour": { "source": "theme" } },
            "press_action": { "animation": "press_action", "colour": { "source": "theme" } },
            "hardware_battery": { "animation": "hardware_battery", "colour": { "source": "battery" } },
            "red_static": { "animation": "solid", "colour": { "source": "fixed", "hex": "ff0000" } },
            "red_breathing": { "animation": "breathing", "colour": { "source": "fixed", "hex": "ff0000" } },
            "off": { "animation": "off", "colour": { "source": "theme" } },
            "none": { "animation": "off", "colour": { "source": "theme" } }
        })

    function normalize(eff: var): var {
        let e = eff;
        if (typeof e === "string")
            e = root._aliases[e] ?? { "animation": "off" };
        if (!e || typeof e !== "object")
            e = {};
        const c = e.colour ?? {};
        let src = c.source ?? "theme";
        if (["theme", "fixed", "battery"].indexOf(src) < 0)
            src = "theme";
        let speed = parseInt(e.speed);
        if (isNaN(speed))
            speed = 3;
        speed = Math.max(1, Math.min(5, speed));
        let dir = e.direction ?? "right";
        if (root.directions.indexOf(dir) < 0)
            dir = "right";
        return {
            "animation": e.animation ?? "solid",
            "colour": { "source": src, "hex": (c.hex ?? "d8bde7").replace(/^#/, "").toLowerCase() },
            "speed": speed,
            "direction": dir
        };
    }

    // Resumen corto de un efecto para cabeceras.
    function summary(eff: var): string {
        const e = root.normalize(eff);
        let s = root.animationLabel(e.animation);
        if (e.animation !== "off" && e.animation !== "neon")
            s += " · " + (root.colourSourceLabels[e.colour.source] ?? e.colour.source);
        return s;
    }
}
