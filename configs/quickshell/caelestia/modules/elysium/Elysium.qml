pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.services

// Elysium — el modo consola. Al conectar un mando sale un aviso arriba a la
// derecha; si no tocas nada en 6 s entra en Elysium (sistema a pantalla
// completa para mando). También ofrece quedarse solo en el modo juego normal.
Scope {
    id: root

    // Biblioteca. `proc` es lo que se busca con pgrep para saber si sigue abierto.
    readonly property var games: [
        {
            "name": "The Legend of Zelda",
            "subtitle": "Ocarina of Time · Hookshot",
            "tag": "N64 · Recompilación nativa",
            "icon": `${Quickshell.env("HOME")}/Games/Hookshot/hookshot.png`,
            "logo": `${Quickshell.env("HOME")}/Games/Hookshot/elysium/oot-logo-light.png`,
            "exec": `env RX_VK_STARTUP_SCREEN=0 RX_VK_NO_WARM=1 RX_VK_PREPARE_BACKGROUND=1 prime-run gamemoderun ${Quickshell.env("HOME")}/Games/Hookshot/hookshot`,
            "proc": "Games/Hookshot/hookshot",
            "wmClass": "hookshot",
            "tint": "#0f1a14"
        }
    ]

    // --- estado ---
    property bool prompt: false
    property string padName: ""
    property int countdown: 6
    property bool active: false       // Elysium encendido
    property bool playing: false      // hay un juego lanzado (la consola se aparta)
    property bool summoned: false     // botón Home durante el juego: la consola vuelve encima
    property var runningGame: null

    property bool ownGameMode: false
    property bool ownDnd: false
    property int prevProfile: PowerProfile.Balanced

    readonly property bool consoleShown: active && (!playing || summoned)

    // --- tele ---
    // La tele es cualquier salida que no sea el panel del portátil (eDP).
    readonly property var tvScreen: Quickshell.screens.find(s => !s.name.startsWith("eDP")) ?? null
    readonly property var laptopScreen: Quickshell.screens.find(s => s.name.startsWith("eDP")) ?? null
    property bool onTv: false
    // Qué hace el portátil mientras se juega en la tele: apoyo | escritorio | apagada
    property string companionMode: "apoyo"
    property date enteredAt: new Date()
    property string prevSink: ""
    readonly property var consoleScreen: onTv ? tvScreen : (Quickshell.screens.find(s => Hypr.monitorFor(s) === Hypr.focusedMonitor) ?? Quickshell.screens[0])

    function setCompanion(mode: string): void {
        if (mode === companionMode)
            return;
        if (companionMode === "apagada")
            Quickshell.execDetached(["brightnessctl", "-r"]);
        if (mode === "apagada")
            Quickshell.execDetached(["brightnessctl", "-s", "set", "0"]);
        companionMode = mode;
    }

    function cycleCompanion(): void {
        setCompanion({ "apoyo": "escritorio", "escritorio": "apagada", "apagada": "apoyo" }[companionMode]);
    }

    function focusTv(): void {
        if (!onTv || !tvScreen)
            return;
        const n = tvScreen.name;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ monitor = "${n}" })` : `focusmonitor ${n}`);
    }

    signal pad(string b)

    function showPrompt(name: string): void {
        if (active)
            return;
        padName = name;
        countdown = 6;
        prompt = true;
    }

    function enterNormal(): void {
        prompt = false;
        GameMode.enabled = true;
        PowerProfiles.profile = PowerProfile.Performance;
    }

    function enter(): void {
        prompt = false;
        if (active)
            return;
        // Marca para `modo-juego`: con Elysium no se para el servicio de Laura.
        Quickshell.execDetached(["touch", `${Quickshell.env("XDG_RUNTIME_DIR")}/elysium-active`]);
        ownGameMode = !GameMode.enabled;
        GameMode.enabled = true;
        prevProfile = PowerProfiles.profile;
        PowerProfiles.profile = PowerProfile.Performance;
        ownDnd = !Notifs.dnd;
        Notifs.dnd = true;
        enteredAt = new Date();
        onTv = tvScreen !== null;
        if (onTv) {
            companionMode = "apoyo";
            // Extender (si estaba en espejo/solo externa) y audio por el HDMI de la tele.
            Quickshell.execDetached(["sh", "-c", `m=$(display-mode status | python3 -c 'import json,sys;print(json.load(sys.stdin)["mode"])'); [ "$m" = extend ] || display-mode extend`]);
            sinkProc.running = true;
        }
        lauraCmd("gamemode on");
        active = true;
    }

    // keepGameMode: salir al escritorio pero dejando el modo juego normal.
    function leave(keepGameMode: bool): void {
        if (!active)
            return;
        active = false;
        summoned = false;
        if (ownDnd)
            Notifs.dnd = false;
        lauraCmd("gamemode off");
        Quickshell.execDetached(["rm", "-f", `${Quickshell.env("XDG_RUNTIME_DIR")}/elysium-active`]);
        if (onTv) {
            setCompanion("apoyo");
            if (prevSink)
                Quickshell.execDetached(["pactl", "set-default-sink", prevSink]);
            prevSink = "";
            onTv = false;
        }
        if (!keepGameMode) {
            if (ownGameMode)
                GameMode.enabled = false;
            PowerProfiles.profile = prevProfile;
        }
    }

    function launch(g: var): void {
        runningGame = g;
        focusTv();
        // La ventana del juego a la tele (las reglas de Hyprland la mandan al workspace «gaming»).
        if (onTv && tvScreen && g.wmClass)
            Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/elysium-tv-move`, g.wmClass, tvScreen.name]);
        Quickshell.execDetached(["setsid", "-f", "sh", "-c", g.exec]);
        playing = true;
        summoned = false;
        aliveTimer.misses = 0;
    }

    // Guarda el sink actual y pasa el audio al HDMI.
    Process {
        id: sinkProc

        command: ["sh", "-c", "pactl get-default-sink; pactl list short sinks | awk '/hdmi/ {print $2; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [cur, hdmi] = text.trim().split("\n");
                if (hdmi && cur !== hdmi) {
                    root.prevSink = cur;
                    Quickshell.execDetached(["pactl", "set-default-sink", hdmi]);
                }
            }
        }
    }

    // --- mando ---
    Process {
        id: watcher

        running: true
        command: [`${Quickshell.env("HOME")}/.local/bin/gamepad-watch`]
        stdout: SplitParser {
            onRead: line => {
                const sp = line.indexOf(" ");
                const kind = line.slice(0, sp);
                const arg = line.slice(sp + 1);
                if (kind === "connected")
                    root.showPrompt(arg);
                else if (kind === "disconnected")
                    root.padName = "";
                else if (kind === "present")
                    root.padName = arg;
                else if (kind === "btn")
                    root.handle(arg);
                else if (kind === "hold" && arg === "home")
                    root.talkToLaura();
            }
        }
        onExited: restartWatcher.start()
    }

    Timer {
        id: restartWatcher

        interval: 3000
        onTriggered: watcher.running = true
    }

    // Home mantenido: hablar con Laura sin soltar el mando (también jugando).
    // Laura sigue viva en Elysium (no se para el servicio como en `modo-juego`):
    // solo pausa la palabra de activación y descarga Ollama entre frases.
    function lauraCmd(cmd: string): void {
        Quickshell.execDetached(["python3", "-c", `import socket,os
try:
    s=socket.socket(socket.AF_UNIX);s.settimeout(1.5);s.connect(os.environ["XDG_RUNTIME_DIR"]+"/laura.sock");s.sendall(b"${cmd}\\n");s.recv(512)
except Exception: pass`]);
    }

    function talkToLaura(): void {
        Quickshell.execDetached(["python3", `${Quickshell.env("HOME")}/proyectos/LinuxRicing/assistant/laura-toggle`, "centro"]);
    }

    function findGame(q: string): var {
        const n = q.toLowerCase();
        return games.find(g => `${g.name} ${g.subtitle} ${g.tag}`.toLowerCase().includes(n)) ?? null;
    }

    function handle(b: string): void {
        if (prompt) {
            if (b === "a" || b === "start")
                enter();
            else if (b === "y")
                enterNormal();
            else if (b === "b")
                prompt = false;
            return;
        }
        // Desde el escritorio: un toque de Home abre Elysium (por si no salió el aviso).
        if (!active) {
            if (b === "home")
                enter();
            return;
        }
        if (playing && !summoned) {
            if (b === "home")
                summoned = true;
            return;
        }
        pad(b);
    }

    // ¿Sigue vivo el juego? Polling barato cada 3 s solo mientras se juega.
    Timer {
        id: aliveTimer

        property int misses: 0

        interval: 3000
        repeat: true
        running: root.playing
        onTriggered: alive.running = true
    }

    Process {
        id: alive

        command: ["pgrep", "-f", root.runningGame?.proc ?? "__none__"]
        onExited: code => {
            if (code === 0) {
                aliveTimer.misses = 0;
                return;
            }
            // Dos fallos seguidos (el lanzador tarda en exec'ear el binario).
            if (++aliveTimer.misses >= 2) {
                root.playing = false;
                root.summoned = false;
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.prompt
        onTriggered: {
            if (--root.countdown <= 0)
                root.enter();
        }
    }

    // --- aviso al conectar el mando ---
    PanelWindow {
        id: promptWin

        visible: root.prompt || card.opacity > 0
        screen: root.consoleScreen
        color: "transparent"
        WlrLayershell.namespace: "caelestia-elysium-prompt"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        anchors.right: true
        implicitWidth: 500
        implicitHeight: 200

        ElysiumPrompt {
            id: card

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 24
            elysium: root
        }
    }

    // --- la consola ---
    LazyLoader {
        id: consoleLoader

        activeAsync: root.active || lingerTimer.running

        ElysiumConsole {
            elysium: root
        }
    }

    // Pantalla de apoyo en el portátil mientras se juega en la tele.
    LazyLoader {
        activeAsync: root.active && root.onTv && root.laptopScreen !== null && root.companionMode !== "escritorio"

        ElysiumCompanion {
            elysium: root
        }
    }

    Timer {
        id: lingerTimer

        interval: 700
    }

    onActiveChanged: if (!active)
        lingerTimer.restart()

    IpcHandler {
        target: "elysium"

        function enter(): void {
            root.enter();
        }

        function leave(): void {
            root.leave(false);
        }

        function prompt(): void {
            root.showPrompt(root.padName || "Mando");
        }

        // Lanza un juego por nombre (entra en Elysium si hace falta). Devuelve el nombre o "".
        function play(name: string): string {
            const g = root.findGame(name);
            if (!g)
                return "";
            root.enter();
            if (!(root.playing && root.runningGame?.proc === g.proc))
                root.launch(g);
            root.summoned = false;
            return `${g.name} · ${g.subtitle}`;
        }

        function list(): string {
            return root.games.map(g => `${g.name} · ${g.subtitle}`).join("\n");
        }

        function status(): string {
            return root.active ? (root.playing ? `jugando: ${root.runningGame?.subtitle ?? "?"}` : "abierto") : "cerrado";
        }

        // apoyo | escritorio | apagada | siguiente
        function companion(mode: string): void {
            if (mode === "siguiente")
                root.cycleCompanion();
            else
                root.setCompanion(mode);
        }

        function toggle(): void {
            if (root.active)
                root.leave(false);
            else
                root.enter();
        }
    }
}
