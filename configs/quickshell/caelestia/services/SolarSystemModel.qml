pragma Singleton
pragma ComponentBehavior: Bound

// SolarSystemModel — el MODELO. Junta la disposición (config, editable por
// Alberto en ~/.config/caelestia/solarsystem.json) con las señales en vivo de
// los adaptadores, y expone ambas para que SolarSystem.qml (la vista) las pinte.
//
// v1.5: adaptadores de música (cava), agentes/terminales (Agents.qml), tareas
// pendientes del backlog, batería real de los tres periféricos
// (mchose-battery --json) y estado de las tres zonas LED (RgbConfig).
// Ver docs/sistema-solar-binario.md.

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Services
import qs.services

Singleton {
    id: root

    // Interruptor global (v1: siempre on; en v3 sustituye a los widgets).
    property bool enabled: true

    // Disposición por defecto. Alberto la reorganiza por JSON en
    // ~/.config/caelestia/solarsystem.json (mismo formato).
    //
    //  - "config": el sol de configuración. Al clicar (v2) lleva a los ajustes
    //    de dispositivos / LEDs. Las tres zonas LED orbitan a su alrededor.
    //  - "laura": la IA de voz. Siempre en el cielo, tenue y lenta en reposo.
    //  - "music": la música como AGUJERO NEGRO, lejos de todo. Los tres
    //    periféricos con batería real orbitan aquí (séquito tipo-S).
    //
    //  NOTA DE DISEÑO (pendiente de Alberto, ver artifact 6935dde1): la v1.5
    //  propone devolver la música a sol dominante y bajar "config" a planeta
    //  interior. Mientras no lo confirme, se mantiene la disposición actual y
    //  solo se completan los cuerpos.
    readonly property var defaultConfig: ({
        anchors: [
            {
                id: "config", label: "Configuración", kind: "sun", color: "primary",
                motion: { kind: "orbit", around: "barycenter", orbit: 28, ecc: 0.45, phase: 0, speed: 0.18 },
                baseSize: 17, baseGlow: 24
            },
            {
                id: "laura", label: "Laura", kind: "sun", color: "secondary",
                motion: { kind: "orbit", around: "barycenter", orbit: 54, ecc: 0.45, phase: 3.14159, speed: 0.18 },
                baseSize: 12, baseGlow: 12,
                dimSignal: "lauraActive"
            },
            {
                id: "music", label: "Música", kind: "blackhole", color: "primary",
                motion: { kind: "fixed", fx: 0.88, fy: 0.26 },
                baseSize: 15,
                sizeSignal: "music"
            }
        ],
        bodies: [
            // --- tres zonas LED, séquito de "config" ---
            {
                id: "led-magichome", kind: "planet", anchor: "config", color: "secondary",
                orbit: 30, ecc: 0.35, phase: 1.0, speed: 0.7, baseSize: 4.5,
                activitySignal: "led:magichome"
            },
            {
                id: "led-akko", kind: "planet", anchor: "config", color: "alt",
                orbit: 38, ecc: 0.35, phase: 3.1, speed: 0.55, baseSize: 4,
                activitySignal: "led:akko"
            },
            {
                id: "led-base", kind: "planet", anchor: "config", color: "belt",
                orbit: 46, ecc: 0.35, phase: 5.0, speed: 0.45, baseSize: 4,
                activitySignal: "led:base"
            },
            // Los tres periféricos con batería real son cuerpos dinámicos: solo
            // aparecen si están conectados (ver _deviceBodies). Un periférico sin
            // señal real se omite, no se pinta un punto gris (principio 5).

            // --- cinturón circumbinario de tareas ---
            {
                id: "tasks", kind: "belt", anchor: "barycenter", color: "belt",
                orbit: 124, ecc: 0.5, phase: 0, speed: 0.05, baseSize: 2,
                activitySignal: "tasks"
            }
        ]
    })

    property var userConfig: null

    // config = disposición + periféricos conectados + terminales en vivo.
    readonly property var config: {
        const base = root.userConfig || root.defaultConfig;
        const bodies = (base.bodies || []).slice();
        const extra = root._deviceBodies().concat(root._terminalBodies());
        for (let i = 0; i < extra.length; i++)
            bodies.push(extra[i]);
        return { anchors: base.anchors || [], bodies: bodies };
    }

    // Periféricos: un cuerpo por dispositivo CONECTADO, séquito del ancla
    // "music". El nivel real llega por la señal batt:<id>.
    function _deviceBodies() {
        const b = root._batt || {};
        const specs = [
            { id: "headset", orbit: 26, phase: 0.4, speed: 0.9 },
            { id: "mouse", orbit: 38, phase: 2.6, speed: 0.7 },
            { id: "keyboard", orbit: 50, phase: 4.6, speed: 0.55 }
        ];
        const out = [];
        for (let i = 0; i < specs.length; i++) {
            const s = specs[i];
            if (typeof b[s.id] !== "number")
                continue; // desconectado: se omite
            out.push({
                id: "dev-" + s.id, kind: "planet", anchor: "music", color: "alt",
                orbit: s.orbit, ecc: 0.4, phase: s.phase, speed: s.speed, baseSize: 5,
                activitySignal: "batt:" + s.id,
                alertSignal: "battLow:" + s.id,
                sizeSignal: "batt:" + s.id
            });
        }
        return out;
    }

    // --- Señales que consumen anclas y cuerpos (0..1 o bool) ---
    property real _music: 0.0
    property int _pendingTasks: 0
    readonly property bool _lauraActive: (Agents.runningAgents || []).length > 0

    // Batería real de los tres periféricos. null = desconectado (cuerpo apagado,
    // solo un aro; nunca un porcentaje inventado — principio 5).
    property var _batt: ({ headset: null, mouse: null, keyboard: null })

    // ¿Hay algo moviéndose? Si no, la vista PARA la animación del todo (el
    // hot-reload de Quickshell fuga los FrameAnimation zombis y un bucle a
    // 60fps clava un núcleo — ver CLAUDE.md). Atado a actividad REAL, nunca a
    // `enabled` a secas.
    readonly property bool musicPlaying: Players.list.some(p => p.isPlaying)
    readonly property bool anyActivity: root.enabled
        && (root.musicPlaying || root._lauraActive || (Agents.runningAgents || []).length > 0)

    readonly property var values: root._buildValues(root._music, root._pendingTasks, root._lauraActive,
                                                    root._batt,
                                                    RgbConfig.devices,
                                                    Agents.runningAgents, Agents.completedAgents)

    function _battFrac(v) {
        return (typeof v === "number" && isFinite(v)) ? Math.max(0, Math.min(1, v / 100)) : 0;
    }

    function _buildValues(music, pending, lauraActive, batt, ledDevices, running, done) {
        const b = batt || {};
        const led = ledDevices || {};
        const v = {
            music: music,
            lauraActive: lauraActive,
            tasks: Math.min(1, pending / 12),

            // Batería: fracción 0..1 para tamaño/actividad; bool para la alerta.
            "batt:headset": root._battFrac(b.headset),
            "batt:mouse": root._battFrac(b.mouse),
            "batt:keyboard": root._battFrac(b.keyboard),
            "battLow:headset": typeof b.headset === "number" && b.headset < 20,
            "battLow:mouse": typeof b.mouse === "number" && b.mouse < 20,
            "battLow:keyboard": typeof b.keyboard === "number" && b.keyboard < 20,

            // LED: refleja si la zona está gestionada por el sync de tema
            // (RgbConfig.devices). No es "encendida" en sentido físico, pero sí
            // un estado real de la config, no un dato inventado.
            "led:magichome": led.magichome ? 1.0 : 0.0,
            "led:akko": led.akko_keyboard ? 1.0 : 0.0,
            "led:base": led.mchose_base ? 1.0 : 0.0
        };
        for (let i = 0; i < (running || []).length; i++)
            v["term:" + (running[i].id || "?")] = 1.0;
        for (let j = 0; j < (done || []).length; j++)
            v["term:" + (done[j].id || "?")] = 0.35;
        return v;
    }

    // ---------- Adaptador: música (cava) ----------
    ServiceRef { service: Audio.cava }

    Timer {
        interval: 40; repeat: true
        running: root.enabled && root.musicPlaying
        onRunningChanged: if (!running) root._music = 0
        onTriggered: {
            const v = Audio.cava.values || [];
            if (!v.length) { root._music *= 0.9; return; }
            let s = 0;
            for (let i = 0; i < v.length; i++) s += v[i];
            const target = Math.min(1, (s / v.length) * 1.6);
            root._music += (target - root._music) * 0.28;
        }
    }

    // ---------- Adaptador: batería real de los periféricos ----------
    // mchose-battery ya trae la lógica hidraw; aquí solo se lee su JSON. Cada
    // 30 s en reposo basta: la batería es una señal lenta. El script cachea en
    // ~/.cache/mchose_battery.json (fresco < 90 s), así que la llamada es barata.
    Process {
        id: battProbe
        command: ["sh", "-c",
            "$HOME/LinuxRicing/rgb/mchose-battery --json 2>/dev/null || mchose-battery --json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text());
                    const pick = o => (o && o.connected && typeof o.battery === "number") ? o.battery : null;
                    root._batt = {
                        headset: pick(d.headset),
                        mouse: pick(d.mouse),
                        keyboard: pick(d.keyboard)
                    };
                } catch (e) {
                    // salida vacía o inválida: se conservan los últimos valores
                }
            }
        }
    }
    Timer {
        interval: 30000; running: root.enabled; repeat: true; triggeredOnStart: true
        onTriggered: battProbe.running = true
    }

    // ---------- Adaptador: agentes / terminales (Agents.qml) ----------
    function _terminalBodies() {
        const running = Agents.runningAgents || [];
        const done = Agents.completedAgents || [];
        const out = [];
        let idx = 0;
        const add = (a, isRunning) => {
            const lane = idx % 2;
            out.push({
                id: "term:" + (a.id || ("t" + idx)),
                kind: "planet",
                anchor: "laura",
                color: /antigrav/i.test(a.name || "") ? "belt" : "alt",
                orbit: 24 + lane * 16,
                ecc: 0.42,
                phase: (idx * 2.399) % (2 * Math.PI),
                speed: (lane ? 1.2 : 1.9) * (isRunning ? 1 : 0.6),
                baseSize: isRunning ? 3.2 : 2.4,
                ring: isRunning,
                activitySignal: "term:" + (a.id || ("t" + idx))
            });
            idx++;
        };
        for (let i = 0; i < running.length; i++) add(running[i], true);
        for (let j = 0; j < done.length; j++) add(done[j], false);
        return out;
    }

    // ---------- Adaptador: tareas pendientes del backlog ----------
    Process {
        id: taskCount
        command: ["sh", "-c",
            "grep -rl 'estado: pendiente' \"$HOME/LinuxRicing/vault/Backlog\" 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(text.trim(), 10);
                if (!isNaN(n))
                    root._pendingTasks = n;
            }
        }
    }
    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: taskCount.running = true
    }

    // ---------- Config del usuario ----------
    FileView {
        path: `${Quickshell.env("HOME")}/.config/caelestia/solarsystem.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.userConfig = (d && (d.anchors || d.bodies)) ? d : null;
            } catch (e) {
                console.warn("SolarSystemModel: solarsystem.json inválido:", e);
                root.userConfig = null;
            }
        }
    }
}
