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
import qs.modules.assistant

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
            "wmClass": "io.github.pixl27.ProjectHookshot",
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

    // Mientras el juego abre, Elysium sigue en pantalla (carga) hasta que la ventana
    // está en su sitio: así la tele nunca enseña el escritorio.
    property bool gameReady: true
    readonly property bool consoleShown: active && (!playing || summoned || !gameReady)

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

    // Reglas de Hyprland mientras se juega en la tele: el workspace «gaming» vive en
    // el HDMI y las ventanas de los juegos de Elysium van a él.
    function tvRules(on: bool): void {
        const off = "for _, r in ipairs({ _G.elyWs, _G.elyWin }) do if r then r:set_enabled(false) end end";
        if (!on || !tvScreen) {
            Quickshell.execDetached(["hyprctl", "eval", off]);
            return;
        }
        const classes = games.map(g => g.wmClass).filter(c => c).join("|");
        const tv = tvScreen.name;
        Quickshell.execDetached(["sh", "-c", `hyprctl eval '${off}; _G.elyWs = hl.workspace_rule({ workspace = "name:gaming", monitor = "${tv}" }); _G.elyWin = hl.window_rule({ match = { class = "^(${classes})$" }, workspace = "name:gaming" })'; hyprctl dispatch 'hl.dsp.workspace.move({ workspace = "name:gaming", monitor = "${tv}" })'`]);
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
            tvRules(true);
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
            tvRules(false);
            onTv = false;
        }
        if (!keepGameMode) {
            if (ownGameMode)
                GameMode.enabled = false;
            PowerProfiles.profile = prevProfile;
        }
    }

    // Cierra el juego abierto (TERM y, si a los 4 s sigue vivo, KILL) y vuelve al menú.
    function closeGame(): void {
        const g = runningGame;
        if (!g)
            return;
        Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/elysium-close`, g.wmClass ?? "", g.proc]);
        playing = false;
        summoned = false;
        gameReady = true;
        runningGame = null;
    }

    function launch(g: var): void {
        runningGame = g;
        focusTv();
        gameReady = !g.wmClass;
        if (g.wmClass) {
            readyProc.command = [`${Quickshell.env("HOME")}/.local/bin/elysium-tv-move`, g.wmClass].concat(onTv && tvScreen ? [tvScreen.name] : []);
            readyProc.running = true;
        }
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

    Process {
        id: readyProc

        stdout: SplitParser {
            onRead: () => root.gameReady = true
        }
        onExited: root.gameReady = true
    }

    // --- mando ---
    Process {
        id: watcher

        running: true
        stdinEnabled: true
        command: [`${Quickshell.env("HOME")}/.local/bin/gamepad-watch`]
        onRunningChanged: if (running)
            write(root.padGrab ? "grab\n" : "ungrab\n")
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
                else if (kind === "hold")
                    root.handleHold(arg);
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

    // Hablar con Laura desde el mando. Solo dispara si está en reposo (empieza a
    // escuchar) o hablando (la corta y escucha): si ya escucha o piensa, un segundo
    // disparo cerraría el ciclo («disparo repetido») y parecía que Laura no iba.
    function talkToLaura(): void {
        if (Laura.state !== "idle" && Laura.state !== "speaking")
            return;
        // Si el servicio está parado (lo para GameMode vía `modo-juego` fuera de Elysium,
        // o el ahorro de batería), se arranca y se espera a su socket antes de activarla.
        const toggle = `python3 ${Quickshell.env("HOME")}/proyectos/LinuxRicing/assistant/laura-toggle centro`;
        const ready = `journalctl --user -u laura.service --since "$t0" -o cat | grep -q "listo. control"`;
        Quickshell.execDetached(["sh", "-c", `systemctl --user is-active -q laura || { t0=$(date '+%F %T'); systemctl --user start laura; i=0; until ${ready} || [ $i -ge 60 ]; do sleep 0.5; i=$((i+1)); done; }; ${toggle}`]);
    }

    // Mantener −/View = Laura (Home no: con xpadneo el botón Xbox es «shift» y
    // mantenerlo apaga el mando).
    function handleHold(b: string): void {
        if (b === "select" || b === "home")
            talkToLaura();
    }

    // Devuelve el foco al juego (al volver del menú) y aparta el cursor de la tele.
    function focusGame(): void {
        const cls = runningGame?.wmClass;
        if (!cls)
            return;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "class:${cls}" })` : `focuswindow class:${cls}`);
        parkCursor();
    }

    // Cursor al centro-abajo del portátil: no tapa el juego y el foco se queda en él.
    function parkCursor(): void {
        if (!onTv || !laptopScreen)
            return;
        const x = laptopScreen.x + Math.round(laptopScreen.width / 2), y = laptopScreen.y + laptopScreen.height - 80;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.cursor.move({ x = ${x}, y = ${y} })` : `movecursor ${x} ${y}`);
    }

    // Con Elysium encima de un juego, el mando es solo de Elysium (si no, cada botón
    // del menú llegaba también al juego).
    readonly property bool padGrab: consoleShown && playing
    onPadGrabChanged: if (watcher.running)
        watcher.write(padGrab ? "grab\n" : "ungrab\n")

    // El foco se pide con retraso: al soltar Elysium el teclado, Hyprland lo devuelve
    // a la ventana anterior y pisaba la orden.
    Timer {
        id: focusTimer

        interval: 400
        onTriggered: root.focusGame()
    }

    onSummonedChanged: if (!summoned && playing && gameReady)
        focusTimer.restart()
    onGameReadyChanged: if (gameReady && playing)
        focusTimer.restart()

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

        // Vivo si existe su ventana o algún proceso del lanzador (antes de que abra la
        // ventana). Con pgrep solo, el binario real (./bin/hookshot) no casaba y Elysium
        // creía que el juego se había cerrado: al volver lo relanzaba.
        command: ["sh", "-c", `hyprctl clients -j | grep -qF '"class": "${root.runningGame?.wmClass ?? "__none__"}"' || pgrep -f '[${(root.runningGame?.proc ?? "__none__")[0]}]${(root.runningGame?.proc ?? "__none__").slice(1)}' >/dev/null`]
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

        // Simula un botón del mando (depuración): a b x y start select home up down left right
        function pad(b: string): void {
            root.handle(b);
        }

        // Simula mantener un botón (depuración): select | home
        function hold(b: string): void {
            root.handleHold(b);
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
