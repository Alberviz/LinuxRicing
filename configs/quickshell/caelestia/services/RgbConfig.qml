pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string path: `${home}/.config/caelestia/rgb-config.json`
    readonly property string syncScript: `${home}/.config/caelestia/sync-rgb.py`

    // Mirrors ~/.config/caelestia/rgb-config.json (see docs/CENTRO_ILUMINACION_RGB_PLAN.md).
    property string source: "theme"                    // "theme" | "fixed"
    property string fixedColour: "d8bde7"              // hex, no leading '#'
    property var devices: ({
            openrgb: true,
            magichome: true,
            mchose_base: true,
            akko_keyboard: true,
            spicetify: true
        })
    property bool openrgbArgbZones: false
    // akko_keyboard y mchose_base usan el objeto de efecto de DeviceEffects
    // (animation/colour/speed/direction); openrgb y magichome siguen con mode/fixed_color.
    property var deviceProfiles: ({
            akko_keyboard: {
                keys: ({ animation: "solid", colour: ({ source: "theme", hex: "d8bde7" }), speed: 3, direction: "right" }),
                sidestrip: ({ animation: "snake", colour: ({ source: "battery", hex: "d8bde7" }), speed: 1, direction: "right" })
            },
            mchose_base: {
                ring: ({ animation: "solid", colour: ({ source: "theme", hex: "d8bde7" }), speed: 3, direction: "right" })
            },
            openrgb: {
                mode: "theme",
                fixed_color: "d8bde7"
            },
            magichome: {
                mode: "theme",
                fixed_color: "d8bde7"
            }
        })
    property bool flashEnabled: false
    property string flashMode: "accent"               // "red" | "accent" | "complementary"
    property int flashPulses: 2
    property var flashDevices: ["mchose_base", "akko_keyboard"]

    property bool loaded: false

    function toJson(): string {
        return JSON.stringify({
            source: root.source,
            fixed_color: root.fixedColour,
            devices: root.devices,
            device_profiles: root.deviceProfiles,
            devices_extra: {
                openrgb: {
                    argb_zones: root.openrgbArgbZones
                }
            },
            notification_flash: {
                enabled: root.flashEnabled,
                mode: root.flashMode,
                pulses: root.flashPulses,
                devices: root.flashDevices
            }
        }, null, 2) + "\n";
    }

    function save(): void {
        if (root.loaded)
            saveTimer.restart();
    }

    // Re-run sync-rgb.py so the change reaches the LEDs without a button press.
    function apply(): void {
        applyTimer.restart();
    }

    function change(): void {
        save();
        apply();
    }

    function setSource(s: string): void {
        root.source = s;
        change();
    }

    function setFixedColour(hex: string): void {
        root.fixedColour = hex.replace(/^#/, "").toLowerCase();
        change();
    }

    function setDevice(key: string, on: bool): void {
        const d = Object.assign({}, root.devices);
        d[key] = on;
        root.devices = d;
        change();
    }

    // Traduce un modo antiguo (string) + color fijo suelto a un objeto de efecto.
    readonly property var _legacyAliases: ({
            "theme": { animation: "solid", source: "theme" },
            "battery_color": { animation: "solid", source: "battery" },
            "breathing": { animation: "breathing", source: "theme" },
            "breathing_battery": { animation: "breathing", source: "battery" },
            "theme_breathing": { animation: "breathing", source: "theme" },
            "wave": { animation: "wave", source: "theme" },
            "wave_battery": { animation: "wave", source: "battery" },
            "stream": { animation: "snake", source: "battery" },
            "stream_battery": { animation: "snake", source: "battery" },
            "reactive_press": { animation: "press_action", source: "theme" },
            "hardware_battery": { animation: "hardware_battery", source: "battery" },
            "off": { animation: "off", source: "theme" }
        })
    function _legacyEffect(mode: string, fixedHex: var): var {
        if (mode === "fixed")
            return {
                animation: "solid",
                colour: { source: "fixed", hex: (fixedHex ?? "d8bde7").replace(/^#/, "").toLowerCase() },
                speed: 3,
                direction: "right"
            };
        const a = root._legacyAliases[mode] ?? { animation: "solid", source: "theme" };
        return {
            animation: a.animation,
            colour: { source: a.source, hex: "d8bde7" },
            speed: a.animation === "snake" ? 1 : 3,
            direction: "right"
        };
    }

    // Guarda el objeto de efecto de una zona del teclado ("keys" | "sidestrip").
    function setAkkoEffect(zone: string, effect: var): void {
        const p = Object.assign({}, root.deviceProfiles);
        const patch = {};
        patch[zone] = effect;
        p.akko_keyboard = Object.assign({}, p.akko_keyboard, patch);
        root.deviceProfiles = p;
        change();
    }

    // Guarda el objeto de efecto del anillo de la base MCHOSE.
    function setMchoseBaseEffect(effect: var): void {
        const p = Object.assign({}, root.deviceProfiles);
        p.mchose_base = Object.assign({}, p.mchose_base, { ring: effect });
        root.deviceProfiles = p;
        change();
    }

    function setDeviceMode(deviceKey: string, m: string): void {
        const p = Object.assign({}, root.deviceProfiles);
        p[deviceKey] = Object.assign({}, p[deviceKey] || {}, { mode: m });
        root.deviceProfiles = p;
        change();
    }

    function setDeviceFixedColor(deviceKey: string, hex: string): void {
        const p = Object.assign({}, root.deviceProfiles);
        p[deviceKey] = Object.assign({}, p[deviceKey] || {}, { fixed_color: hex.replace(/^#/, "").toLowerCase() });
        root.deviceProfiles = p;
        change();
    }

    function setOpenrgbArgbZones(on: bool): void {
        root.openrgbArgbZones = on;
        // The animated wave over the RAM + fan headers is a systemd --user
        // daemon (argb-wave.service). Toggle it and persist across reboots.
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", "argb-wave.service"]);
        change();
    }

    function setFlashEnabled(on: bool): void {
        root.flashEnabled = on;
        save();
    }

    function setFlashMode(m: string): void {
        root.flashMode = m;
        save();
    }

    function setFlashPulses(n: int): void {
        root.flashPulses = Math.max(1, Math.min(5, n));
        save();
    }

    function setFlashDevice(key: string, on: bool): void {
        const s = new Set(root.flashDevices);
        if (on)
            s.add(key);
        else
            s.delete(key);
        root.flashDevices = [...s];
        save();
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: view.setText(root.toJson())
    }

    Timer {
        id: applyTimer
        interval: 500
        onTriggered: Quickshell.execDetached(["/usr/bin/python3", root.syncScript])
    }

    FileView {
        id: view

        path: root.path
        printErrors: false

        onLoaded: {
            try {
                const c = JSON.parse(view.text());
                if (c.source === "theme" || c.source === "fixed")
                    root.source = c.source;
                if (typeof c.fixed_color === "string")
                    root.fixedColour = c.fixed_color.replace(/^#/, "").toLowerCase();
                if (c.devices && typeof c.devices === "object")
                    root.devices = Object.assign({}, root.devices, c.devices);
                if (c.device_profiles && typeof c.device_profiles === "object") {
                    const merged = Object.assign({}, root.deviceProfiles);
                    for (const k in c.device_profiles) {
                        merged[k] = Object.assign({}, merged[k] || {}, c.device_profiles[k]);
                    }
                    // Migrar el perfil antiguo del teclado ({keys_mode, keys_fixed_color,
                    // sidestrip_mode, ...}) al objeto de efecto nuevo {keys, sidestrip}.
                    const ak = merged.akko_keyboard || {};
                    if (ak.keys === undefined && (ak.keys_mode !== undefined || ak.sidestrip_mode !== undefined)) {
                        const legacy = m => {
                            if (m === "battery_meter_keys" || m === "battery_meter_rows")
                                m = "breathing_battery";
                            return m;
                        };
                        merged.akko_keyboard = {
                            keys: root._legacyEffect(legacy(ak.keys_mode ?? "theme"), ak.keys_fixed_color),
                            sidestrip: root._legacyEffect(legacy(ak.sidestrip_mode ?? "stream_battery"), ak.sidestrip_fixed_color)
                        };
                    }
                    // Base MCHOSE: {mode, fixed_color} -> {ring: <efecto>}
                    const mb = merged.mchose_base || {};
                    if (mb.ring === undefined && mb.mode !== undefined)
                        merged.mchose_base = { ring: root._legacyEffect(mb.mode, mb.fixed_color) };
                    root.deviceProfiles = merged;
                }
                if (c.devices_extra && c.devices_extra.openrgb && c.devices_extra.openrgb.argb_zones !== undefined)
                    root.openrgbArgbZones = !!c.devices_extra.openrgb.argb_zones;
                const f = c.notification_flash ?? {};
                if (f.enabled !== undefined)
                    root.flashEnabled = !!f.enabled;
                if (typeof f.mode === "string")
                    root.flashMode = f.mode;
                if (typeof f.pulses === "number")
                    root.flashPulses = f.pulses;
                if (Array.isArray(f.devices))
                    root.flashDevices = f.devices;
            } catch (e) {
                console.warn("RgbConfig: bad rgb-config.json:", e);
            }
            root.loaded = true;
        }

        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => view.setText(root.toJson()));
        }
    }
}
