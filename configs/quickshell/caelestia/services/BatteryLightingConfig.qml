pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Mirrors ~/.config/caelestia/battery-lighting.json — the config the
// `battery-lighting` daemon reads (see docs/superpowers/specs/
// 2026-08-27-battery-lighting-engine-design.md and rgb/battery-lighting).
//
// This singleton owns ONLY the UI-facing shape of that file. The daemon is
// the authority: it seeds/migrates the file on first `--tick`, validates
// every write, and applies the rules. After every save here we fire
// `battery-lighting --tick` so the change reaches the LEDs without waiting
// for the daemon's poll.
//
// The VALID_*/EFFECTS tables below are a hand-copy of the daemon's
// (rgb/battery-lighting lines ~69-83). Keep them in sync — a mismatch shows
// up as a chip the daemon silently drops.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string path: `${home}/.config/caelestia/battery-lighting.json`
    readonly property string binPath: `${home}/.local/bin/battery-lighting`

    // --- state mirrored from disk ---
    // rules: [{ id, source, trigger, threshold|null, actions: [{ target, zone|null, effect }] }]
    property var rules: []
    property int criticalThreshold: 10
    // carried through untouched on save (not exposed in the UI)
    property var poll: ({
            idle_seconds: 15,
            charging_seconds: 3
        })
    property bool loaded: false
    property bool seeding: false

    // --- vocab (Spanish labels; keys must match the daemon) ---
    readonly property var sources: [
        { key: "akko_keyboard", label: qsTr("Teclado Akko"), icon: "keyboard" },
        { key: "mchose_mouse", label: qsTr("Ratón K7 Ultra"), icon: "mouse" },
        { key: "v9_headset", label: qsTr("Auriculares V9 Pro"), icon: "headphones" }
    ]
    readonly property var triggers: [
        { key: "charging", label: qsTr("Al cargar") },
        { key: "low", label: qsTr("Batería baja") },
        { key: "critical", label: qsTr("Batería crítica") }
    ]
    // v9_headset is source-only (no addressable RGB); never a target.
    readonly property var targets: [
        { key: "mchose_base", label: qsTr("Anillo de la base"), icon: "mouse", hasZones: false },
        { key: "akko_keyboard", label: qsTr("Teclado Akko"), icon: "keyboard", hasZones: true },
        { key: "magichome", label: qsTr("Tira MagicHome"), icon: "lightbulb", hasZones: false },
        { key: "openrgb", label: qsTr("Torre · placa / RAM / ventiladores"), icon: "developer_board", hasZones: false }
    ]
    readonly property var zones: [
        { key: "keys", label: qsTr("Teclas") },
        { key: "sidestrip", label: qsTr("Tira lateral") },
        { key: "both", label: qsTr("Ambas") }
    ]

    readonly property var effectLabels: ({
            theme: qsTr("Color del tema"),
            solid_theme: qsTr("Fijo (tema)"),
            theme_breathing: qsTr("Respiración (tema)"),
            battery_meter: qsTr("Medidor de batería"),
            battery_color: qsTr("Color según nivel"),
            breathing_battery: qsTr("Respiración (color batería)"),
            breathing: qsTr("Respiración"),
            wave: qsTr("Ola"),
            wave_battery: qsTr("Ola (color batería)"),
            stream: qsTr("Flujo"),
            stream_battery: qsTr("Flujo color batería"),
            hardware_battery: qsTr("Batería del firmware"),
            red: qsTr("Rojo"),
            red_breathing: qsTr("Rojo respiración"),
            red_static: qsTr("Rojo fijo"),
            none: qsTr("Ninguno")
        })

    // El teclado Akko solo admite efectos de firmware de una sola escritura; el
    // lienzo per-key (battery_meter) se retiró porque congela el teclado ~1 s por
    // pasada sobre 2.4 GHz. 'stream' solo vale en la tira lateral (en las teclas
    // el modo 5 es Ripple). Mantener en sync con rgb/battery-lighting EFFECTS.
    readonly property var _effects: ({
            "akko_keyboard:keys": ["theme", "breathing_battery", "breathing", "wave", "wave_battery", "red_breathing", "red_static", "none"],
            "akko_keyboard:sidestrip": ["stream_battery", "breathing", "solid_theme", "red_breathing", "red_static", "none"],
            "mchose_base": ["theme_breathing", "battery_color", "hardware_battery", "wave", "red_breathing", "red_static", "none"],
            "magichome": ["battery_color", "solid_theme", "red", "none"],
            "openrgb": ["battery_meter", "solid_theme", "red", "none"]
        })

    // akko_keyboard y mchose_base usan el objeto de efecto (EffectEditor);
    // magichome/openrgb siguen con esta lista de strings.
    function usesEffectObject(target: string): bool {
        return target === "akko_keyboard" || target === "mchose_base";
    }

    // [{ key, label }] para magichome/openrgb.
    function effectsFor(target: string, zone: string): var {
        const keys = root._effects[target] ?? [];
        return keys.map(e => ({
                    key: e,
                    label: root.effectLabels[e] ?? e
                }));
    }

    readonly property var _migrateAliases: ({
            "theme": { animation: "solid", source: "theme" },
            "solid_theme": { animation: "solid", source: "theme" },
            "battery_color": { animation: "solid", source: "battery" },
            "breathing": { animation: "breathing", source: "theme" },
            "breathing_battery": { animation: "breathing", source: "battery" },
            "theme_breathing": { animation: "breathing", source: "theme" },
            "wave": { animation: "wave", source: "theme" },
            "wave_battery": { animation: "wave", source: "battery" },
            "stream": { animation: "snake", source: "battery" },
            "stream_battery": { animation: "snake", source: "battery" },
            "hardware_battery": { animation: "hardware_battery", source: "battery" },
            "battery_meter": { animation: "breathing", source: "battery" },
            "red_static": { animation: "solid", source: "fixed", hex: "ff0000" },
            "red_breathing": { animation: "breathing", source: "fixed", hex: "ff0000" },
            "none": { animation: "off", source: "theme" }
        })
    function _migrateEffect(str: string): var {
        const a = root._migrateAliases[str] ?? { animation: "solid", source: "theme" };
        return {
            animation: a.animation,
            colour: { source: a.source, hex: a.hex ?? "d8bde7" },
            speed: a.animation === "snake" ? 1 : 3,
            direction: "right"
        };
    }

    // Efecto por defecto al elegir un destino nuevo.
    function defaultEffectFor(target: string, zone: string): var {
        if (target === "akko_keyboard")
            return { animation: (zone === "sidestrip" ? "snake" : "breathing"),
                     colour: { source: "battery", hex: "d8bde7" }, speed: 3, direction: "right" };
        if (target === "mchose_base")
            return { animation: "breathing", colour: { source: "battery", hex: "d8bde7" },
                     speed: 3, direction: "right" };
        return (root._effects[target] ?? ["none"])[0];
    }

    function sourceLabel(key: string): string {
        return (root.sources.find(s => s.key === key) ?? {}).label ?? key;
    }
    function triggerLabel(key: string): string {
        return (root.triggers.find(t => t.key === key) ?? {}).label ?? key;
    }
    function targetLabel(key: string): string {
        return (root.targets.find(t => t.key === key) ?? {}).label ?? key;
    }
    function targetHasZones(key: string): bool {
        return !!(root.targets.find(t => t.key === key) ?? {}).hasZones;
    }

    // --- serialisation ---
    function toJson(): string {
        const out = {
            poll: {
                idle_seconds: root.poll.idle_seconds ?? 15,
                charging_seconds: root.poll.charging_seconds ?? 3
            },
            critical_threshold: root.criticalThreshold,
            rules: root.rules.map(r => {
                const rule = {
                    id: r.id,
                    source: r.source,
                    trigger: r.trigger,
                    threshold: r.trigger === "low" ? (r.threshold ?? 20) : null,
                    actions: (r.actions ?? []).map(a => {
                        const act = { target: a.target, effect: a.effect };
                        if (a.target === "akko_keyboard" && a.zone)
                            act.zone = a.zone;
                        return act;
                    })
                };
                return rule;
            })
        };
        return JSON.stringify(out, null, 2) + "\n";
    }

    // --- mutation helpers (replace arrays so QML sees the change) ---
    function _commit(newRules): void {
        root.rules = newRules;
        root.save();
    }
    function _rule(id: string): var {
        return root.rules.find(r => r.id === id) ?? null;
    }

    function addRule(source: string, trigger: string): void {
        const id = `${source}-${trigger}-${Date.now().toString(36)}`;
        const rule = {
            id,
            source,
            trigger,
            threshold: trigger === "low" ? 20 : null,
            actions: []
        };
        _commit([...root.rules, rule]);
    }

    function removeRule(id: string): void {
        _commit(root.rules.filter(r => r.id !== id));
    }

    function setRuleThreshold(id: string, n: int): void {
        const v = Math.min(40, Math.max(5, Math.round(n / 5) * 5));
        _commit(root.rules.map(r => r.id === id ? Object.assign({}, r, { threshold: v }) : r));
    }

    function setPollIdleSeconds(secs: int): void {
        const v = Math.max(10, Math.min(300, Math.round(secs / 5) * 5));
        root.poll = Object.assign({}, root.poll, { idle_seconds: v });
        root.save();
    }

    function addAction(ruleId: string, target: string, zone: var): void {
        _commit(root.rules.map(r => {
            if (r.id !== ruleId)
                return r;
            const z = target === "akko_keyboard" ? (zone || "keys") : undefined;
            const a = { target, effect: root.defaultEffectFor(target, z) };
            if (z)
                a.zone = z;
            return Object.assign({}, r, { actions: [...(r.actions ?? []), a] });
        }));
    }

    function updateAction(ruleId: string, index: int, patch: var): void {
        _commit(root.rules.map(r => {
            if (r.id !== ruleId)
                return r;
            const actions = (r.actions ?? []).map((a, i) => {
                if (i !== index)
                    return a;
                const next = Object.assign({}, a, patch);
                if (next.target !== "akko_keyboard")
                    delete next.zone;
                else if (!next.zone)
                    next.zone = "keys";
                // Si cambió el destino/zona, dar un efecto válido para el nuevo.
                if ((patch.target && patch.target !== a.target) || (patch.zone && patch.zone !== a.zone)) {
                    next.effect = root.defaultEffectFor(next.target, next.zone);
                } else if (!root.usesEffectObject(next.target)) {
                    const valid = root.effectsFor(next.target, next.zone).map(e => e.key);
                    if (!valid.includes(next.effect))
                        next.effect = valid[0];
                }
                return next;
            });
            return Object.assign({}, r, { actions });
        }));
    }

    function removeAction(ruleId: string, index: int): void {
        _commit(root.rules.map(r => r.id === ruleId ? Object.assign({}, r, {
            actions: (r.actions ?? []).filter((a, i) => i !== index)
        }) : r));
    }

    // Fire one rule's effects right now (the "Probar" button).
    function probe(ruleId: string): void {
        Quickshell.execDetached([root.binPath, "--apply", ruleId]);
    }

    function save(): void {
        if (root.loaded && !root.seeding)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 250
        onTriggered: {
            view.setText(root.toJson());
            applyTimer.restart();
        }
    }

    Timer {
        id: applyTimer
        interval: 400
        onTriggered: Quickshell.execDetached([root.binPath, "--tick"])
    }

    // The daemon seeds/migrates the file on its first tick; retry-read after.
    Timer {
        id: seedTimer
        interval: 800
        onTriggered: view.reload()
    }

    FileView {
        id: view

        path: root.path
        printErrors: false
        watchChanges: true

        onFileChanged: reload()

        onLoaded: {
            root.seeding = false;
            try {
                const c = JSON.parse(view.text());
                if (c.poll && typeof c.poll === "object")
                    root.poll = Object.assign({}, root.poll, c.poll);
                if (typeof c.critical_threshold === "number")
                    root.criticalThreshold = c.critical_threshold;
                if (Array.isArray(c.rules)) {
                    root.rules = c.rules.map(r => ({
                                id: String(r.id ?? `rule-${Math.random().toString(36).slice(2)}`),
                                source: r.source,
                                trigger: r.trigger,
                                threshold: (r.trigger === "low") ? (r.threshold ?? 20) : null,
                                actions: Array.isArray(r.actions) ? r.actions.map(a => ({
                                            target: a.target,
                                            zone: a.zone ?? null,
                                            effect: root.usesEffectObject(a.target) && typeof a.effect === "string"
                                                ? root._migrateEffect(a.effect)
                                                : a.effect
                                        })) : []
                            }));
                }
            } catch (e) {
                console.warn("BatteryLightingConfig: bad battery-lighting.json:", e);
            }
            root.loaded = true;
        }

        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound && !root.seeding) {
                // Ask the daemon to seed + migrate the file, then re-read.
                root.seeding = true;
                Quickshell.execDetached([root.binPath, "--tick"]);
                seedTimer.restart();
            }
            root.loaded = true;
        }
    }
}
