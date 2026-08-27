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
            idle_seconds: 60,
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
            stream: qsTr("Flujo"),
            stream_battery: qsTr("Flujo color batería"),
            hardware_battery: qsTr("Batería del firmware"),
            wave: qsTr("Ola"),
            red: qsTr("Rojo"),
            red_breathing: qsTr("Rojo respiración"),
            red_static: qsTr("Rojo fijo"),
            none: qsTr("Ninguno")
        })

    readonly property var _effects: ({
            "akko_keyboard:keys": ["theme", "battery_meter", "breathing_battery", "stream", "red_breathing", "red_static", "none"],
            "akko_keyboard:sidestrip": ["stream_battery", "breathing", "solid_theme", "red_breathing", "red_static", "none"],
            "mchose_base": ["theme_breathing", "battery_color", "hardware_battery", "wave", "red_breathing", "red_static", "none"],
            "magichome": ["battery_color", "solid_theme", "red", "none"],
            "openrgb": ["battery_meter", "solid_theme", "red", "none"]
        })

    // Returns [{ key, label }] for a target (+ zone if the target is the Akko).
    function effectsFor(target: string, zone: string): var {
        let k = target;
        if (target === "akko_keyboard")
            k = `akko_keyboard:${zone === "sidestrip" ? "sidestrip" : "keys"}`;
        const keys = root._effects[k] ?? [];
        return keys.map(e => ({
                    key: e,
                    label: root.effectLabels[e] ?? e
                }));
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
                idle_seconds: root.poll.idle_seconds ?? 60,
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

    function addAction(ruleId: string, target: string, zone: var, effect: string): void {
        _commit(root.rules.map(r => {
            if (r.id !== ruleId)
                return r;
            const a = { target, effect };
            if (target === "akko_keyboard")
                a.zone = zone || "keys";
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
                // clamp effect to what's valid for the new target/zone
                const valid = root.effectsFor(next.target, next.zone).map(e => e.key);
                if (!valid.includes(next.effect))
                    next.effect = valid[0];
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
                                            effect: a.effect
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
