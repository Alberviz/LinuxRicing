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

    // v3: el wallpaper se apaga y el escritorio queda sobre fondo negro
    // (decisión D-1, restaurable). Poner a true devuelve el wallpaper; la paleta
    // sigue saliendo de Colours.palette en cualquier caso.
    property bool showWallpaper: false

    // Disposición por defecto de la v3 (variante D). Alberto la afina por JSON en
    // ~/.config/caelestia/solarsystem.json (mismo formato).
    //
    //  - "music": la música como AGUJERO NEGRO masivo, clavado en la esquina
    //    superior derecha, saliéndose de cuadro. No traslada; sólo rota.
    //  - "config": sol SECUNDARIO del binario. Ancla y (futuro) objetivo de clic
    //    para los ajustes de dispositivos. Los dispositivos conectados lo orbitan.
    //  - "laura": sol PRIMARIO del binario (mayor, con prominencias). Los agentes
    //    la orbitan. El baricentro Laura↔Config está ANCLADO en pantalla (no
    //    deriva alrededor del agujero — decisión D-2).
    //
    //  Las zonas LED NO se dibujan en esta tanda (D-5); el adaptador se queda.
    //  La reactividad (Laura se aviva al estar activa) es de una tanda posterior
    //  (D-7): Laura no lleva dimSignal.
    readonly property var defaultConfig: ({
        anchors: [
            {
                id: "music", label: "Música", kind: "blackhole",
                motion: { kind: "fixed", fx: 1.02, fy: -0.04 }, rFrac: 0.24
            },
            {
                id: "config", label: "Configuración", kind: "sun", role: "secondary",
                rFrac: 0.035
            },
            {
                id: "laura", label: "Laura", kind: "sun", role: "primary",
                rFrac: 0.045
            }
        ],
        bodies: [
            // Agentes (séquito de Laura) y dispositivos con batería real (séquito
            // de Config) son cuerpos DINÁMICOS: sólo aparecen si hay señal real
            // (ver _terminalBodies / _deviceBodies). Un cuerpo sin señal no se
            // pinta (principio 5).

            // --- cinturón circumbinario de tareas ---
            {
                id: "tasks", kind: "belt", anchor: "barycenter", rxFrac: 0.14,
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

    // Dispositivos: un cuerpo por periférico CONECTADO, séquito del sol de
    // Configuración. Tamaño y brillo = % de batería real; aro rojo si < 20 %.
    function _deviceBodies() {
        const b = root._batt || {};
        const specs = [
            { id: "headset", orbitK: 2.0, phase: 0.4, period: 80 },
            { id: "mouse", orbitK: 2.9, phase: 2.6, period: 88 },
            { id: "keyboard", orbitK: 3.7, phase: 4.6, period: 96 }
        ];
        const out = [];
        for (let i = 0; i < specs.length; i++) {
            const s = specs[i];
            if (typeof b[s.id] !== "number")
                continue; // desconectado: se omite
            out.push({
                id: "dev-" + s.id, kind: "planet", anchor: "config",
                orbitK: s.orbitK, phase: s.phase, period: s.period,
                activitySignal: "batt:" + s.id,
                alertSignal: "battLow:" + s.id,
                sizeSignal: "batt:" + s.id
            });
        }
        return out;
    }

    // --- Señales que consumen anclas y cuerpos (0..1 o bool) ---
    // Música: cuatro señales derivadas del array de bandas FFT de cava.
    //  _music       energía global (media de todas las bandas). NO tocar: ya la
    //               consume el shader con este nombre y comportamiento.
    //  _musicBass   energía del primer 25 % del array (graves).
    //  _musicTreble energía del último 30 % del array (agudos).
    //  _musicPulse  detector de golpe: 1 de golpe cuando la energía instantánea
    //               supera su media móvil lenta por un margen, luego decae expo.
    //  _musicAvgSlow media móvil lenta de la energía instantánea (interna, base
    //               del detector de golpe; no se expone).
    property real _music: 0.0
    property real _musicBass: 0.0
    property real _musicTreble: 0.0
    property real _musicPulse: 0.0
    property real _musicAvgSlow: 0.0
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

    readonly property var values: root._buildValues(root._music, root._musicBass, root._musicTreble,
                                                    root._musicPulse,
                                                    root._pendingTasks, root._lauraActive,
                                                    root._batt,
                                                    RgbConfig.devices,
                                                    Agents.runningAgents, Agents.completedAgents)

    function _battFrac(v) {
        return (typeof v === "number" && isFinite(v)) ? Math.max(0, Math.min(1, v / 100)) : 0;
    }

    function _buildValues(music, musicBass, musicTreble, musicPulse, pending, lauraActive, batt, ledDevices, running, done) {
        const b = batt || {};
        const led = ledDevices || {};
        const v = {
            music: music,
            musicBass: musicBass,
            musicTreble: musicTreble,
            musicPulse: musicPulse,
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
        onRunningChanged: {
            if (!running) {
                // Sin música: las cuatro señales a 0, nada clavado.
                root._music = 0;
                root._musicBass = 0;
                root._musicTreble = 0;
                root._musicPulse = 0;
                root._musicAvgSlow = 0;
            }
        }
        onTriggered: {
            const v = Audio.cava.values || [];
            if (!v.length) {
                // cava sin datos: decaimiento, nunca dato inventado (principio 5).
                root._music *= 0.9;
                root._musicBass *= 0.9;
                root._musicTreble *= 0.9;
                root._musicPulse *= 0.6;
                root._musicAvgSlow *= 0.95;
                return;
            }
            const n = v.length;

            // --- energía global (idéntico al comportamiento previo) ---
            let s = 0;
            for (let i = 0; i < n; i++) s += v[i];
            const mean = s / n;
            const target = Math.min(1, mean * 1.6);
            root._music += (target - root._music) * 0.28;

            // --- graves: primer 25 % del array ---
            // Los graves suelen ser la parte más caliente del espectro, así que
            // el factor va por debajo del de la energía global para no saturar.
            const bassEnd = Math.max(1, Math.round(n * 0.25));
            let bs = 0;
            for (let i = 0; i < bassEnd; i++) bs += v[i];
            const bassTarget = Math.min(1, (bs / bassEnd) * 1.3);
            root._musicBass += (bassTarget - root._musicBass) * 0.28;

            // --- agudos: último 30 % del array ---
            // Los agudos vienen bastante bajos; factor más alto para que el
            // rango útil sea amplio y no quede pegado a 0.
            const trebStart = Math.min(n - 1, Math.round(n * 0.70));
            const trebCount = n - trebStart;
            let ts = 0;
            for (let i = trebStart; i < n; i++) ts += v[i];
            const trebTarget = Math.min(1, (ts / trebCount) * 2.8);
            root._musicTreble += (trebTarget - root._musicTreble) * 0.28;

            // --- detector de golpe (musicPulse) ---
            // Media móvil lenta de la energía instantánea SIN suavizar (mean),
            // constante de tiempo ~0.6 s (0.06 por tick de 40 ms). Cuando la
            // energía instantánea supera esa media por un margen del 35 %,
            // dispara el pulso a 1; si no, decae expo (0.6/tick → ~0 en ~200 ms).
            // El margen relativo hace que un pasaje sostenido y fuerte levante la
            // media y deje de disparar: sólo los picos reales cuentan.
            root._musicAvgSlow += (mean - root._musicAvgSlow) * 0.06;
            const thresh = root._musicAvgSlow * 1.35 + 0.02;
            if (mean > thresh && root._musicAvgSlow > 0.015)
                root._musicPulse = 1.0;
            else
                root._musicPulse *= 0.6;
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
    // Un satélite por sesión de Claude/Antigravity, séquito de Laura. En curso →
    // brillante, con anillo de actividad, órbita más rápida y cerrada.
    // Completado → tenue, órbita más lenta y más abierta. 0 agentes → 0 cuerpos.
    function _terminalBodies() {
        const running = Agents.runningAgents || [];
        const done = Agents.completedAgents || [];
        const out = [];
        let idx = 0;
        const add = (a, isRunning) => {
            const lane = idx % 3;
            out.push({
                id: "term:" + (a.id || ("t" + idx)),
                kind: "planet",
                anchor: "laura",
                phase: (idx * 2.399) % (2 * Math.PI),
                orbitK: isRunning ? (2.1 + lane * 0.85) : (3.4 + lane * 1.0),
                period: isRunning ? (46 + lane * 7) : (118 + lane * 12),
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
