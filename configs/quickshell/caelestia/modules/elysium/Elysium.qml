pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant
import QtMultimedia

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
            "updates": "hookshot",
            "exec": `env HOOKSHOT_SKIP_UPDATE_CHECK=1 RX_VK_STARTUP_SCREEN=0 RX_VK_NO_WARM=1 RX_VK_PREPARE_BACKGROUND=1 prime-run gamemoderun ${Quickshell.env("HOME")}/Games/Hookshot/hookshot`,
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
        sfx("prompt");
    }

    function enterNormal(): void {
        prompt = false;
        GameMode.enabled = true;
        PowerProfiles.profile = PowerProfile.Performance;
    }

    // Jugar en la tele (si está conectada) o en el portátil. Se recuerda entre sesiones.
    // Escritorio que tenía la tele al entrar: se le devuelve al salir (si no, se quedaba
    // en el workspace «gaming» vacío y no se podía usar para trabajar).
    property string prevTvWs: ""

    function tvSetup(): void {
        onTv = true;
        const ws = Hypr.monitorFor(tvScreen)?.activeWorkspace?.name ?? "";
        prevTvWs = ws === "gaming" ? "" : ws;
        companionMode = "apoyo";
        // Extender (si estaba en espejo/solo externa) y audio por el HDMI de la tele.
        Quickshell.execDetached(["sh", "-c", `m=$(display-mode status | python3 -c 'import json,sys;print(json.load(sys.stdin)["mode"])'); [ "$m" = extend ] || display-mode extend`]);
        sinkProc.running = true;
        tvRules(true);
    }

    function tvTeardown(): void {
        setCompanion("apoyo");
        // Volver al audio de antes; si no había (ya estaba en el HDMI), a unos cascos
        // (USB/Bluetooth) o, si no, a los altavoces del portátil.
        if (prevSink)
            setSink(prevSink);
        else
            audioOffHdmi();
        prevSink = "";
        tvRules(false);
        restoreTvWorkspace();
        onTv = false;
    }

    function restoreTvWorkspace(): void {
        if (!tvScreen)
            return;
        const tv = tvScreen.name, back = laptopScreen?.name ?? "";
        // Sin escritorio previo: el primer número libre a partir del 6 (no roba uno del portátil).
        const ws = prevTvWs || "$(hyprctl workspaces -j | python3 -c 'import json,sys; u={w[\"name\"] for w in json.load(sys.stdin)}; print(next(str(n) for n in range(6,20) if str(n) not in u))')";
        prevTvWs = "";
        if (Hypr.usingLua)
            Quickshell.execDetached(["sh", "-c", `hyprctl dispatch 'hl.dsp.focus({ monitor = "${tv}" })'; hyprctl dispatch "hl.dsp.focus({ workspace = \"${ws}\" })"; ${back ? `hyprctl dispatch 'hl.dsp.focus({ monitor = "${back}" })'` : ""}`]);
    }

    // Cambia la salida por defecto Y mueve lo que ya suena: los flujos de Qt (música y
    // efectos de Elysium) quedan fijados a la salida de cuando se crearon
    // (node.dont-reconnect) y, sin esto, seguían sonando en los cascos con la tele puesta.
    function setSink(sink: string): void {
        Quickshell.execDetached(["sh", "-c", `pactl set-default-sink '${sink}'; for r in 0 1.5; do sleep $r; for i in $(pactl list short sink-inputs | cut -f1); do pactl move-sink-input $i '${sink}'; done; done`]);
    }

    function audioOffHdmi(): void {
        Quickshell.execDetached(["sh", "-c", "cur=$(pactl get-default-sink); case $cur in *hdmi*) s=$(pactl list short sinks | awk '{print $2}' | grep -E 'bluez|usb' | head -n1); [ -n \"$s\" ] || s=$(pactl list short sinks | awk '{print $2}' | grep -v hdmi | head -n1); [ -n \"$s\" ] && { pactl set-default-sink \"$s\"; for i in $(pactl list short sink-inputs | cut -f1); do pactl move-sink-input $i \"$s\"; done; };; esac"]);
    }

    function setPlayOnTv(v: bool): void {
        prefs.playOnTv = v;
        if (!active)
            return;
        if (v && tvScreen && !onTv)
            tvSetup();
        else if (!v && onTv)
            tvTeardown();
    }

    // --- Laura por juego ---
    property bool lauraStoppedForGame: false

    function lauraFor(g: var): bool {
        return g?.proc ? (prefs.lauraOff.indexOf(g.proc) < 0) : true;
    }

    function setLauraFor(g: var, on: bool): void {
        if (!g?.proc)
            return;
        const l = prefs.lauraOff.filter(p => p !== g.proc);
        if (!on)
            l.push(g.proc);
        prefs.lauraOff = l;
        // Si ese juego está abierto, aplicarlo ya.
        if (playing && runningGame?.proc === g.proc) {
            if (!on && LauraService.state !== "off") {
                lauraStoppedForGame = true;
                LauraService.stop();
            } else if (on && lauraStoppedForGame) {
                lauraStoppedForGame = false;
                LauraService.start();
            }
        }
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
        if (tvScreen !== null && playOnTv)
            tvSetup();
        else if (tvScreen !== null)
            audioOffHdmi();  // tele conectada pero se juega en el portátil
        lauraCmd("gamemode on");
        active = true;
        sfx("open");
        hookshotCheck(false);
    }

    // keepGameMode: salir al escritorio pero dejando el modo juego normal.
    function leave(keepGameMode: bool): void {
        if (!active)
            return;
        active = false;
        summoned = false;
        hideIdleCursor(false);
        sfx("close");
        if (ownDnd)
            Notifs.dnd = false;
        lauraCmd("gamemode off");
        Quickshell.execDetached(["rm", "-f", `${Quickshell.env("XDG_RUNTIME_DIR")}/elysium-active`]);
        if (onTv)
            tvTeardown();
        if (lauraStoppedForGame) {
            lauraStoppedForGame = false;
            LauraService.start();
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
        restoreLauraAfterGame();
        Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/elysium-close`, g.wmClass ?? "", g.proc]);
        playing = false;
        summoned = false;
        gameReady = true;
        runningGame = null;
    }

    function restoreLauraAfterGame(): void {
        if (lauraStoppedForGame) {
            lauraStoppedForGame = false;
            LauraService.start();
        }
    }

    // ================= Sonidos =================
    function sfx(name: string): void {
        if (!prefs.sound)
            return;
        const e = sfxObj[name];
        if (e) {
            e.stop();
            e.play();
        }
    }

    readonly property var sfxObj: ({
            "move": sMove,
            "select": sSelect,
            "back": sBack,
            "dialog": sDialog,
            "toggle_on": sOn,
            "toggle_off": sOff,
            "prompt": sPrompt,
            "error": sError,
            "success": sSuccess,
            "open": sOpen,
            "close": sClose,
            "launch": sLaunch
        })

    // Salida de audio: siempre la que el sistema tenga por defecto (tele, cascos…).
    MediaDevices {
        id: mediaDevices
    }

    component Sfx: SoundEffect {
        volume: 0.7
        audioDevice: mediaDevices.defaultAudioOutput
    }

    Sfx { id: sMove; source: Qt.resolvedUrl("sounds/move.wav"); volume: 0.5 }
    Sfx { id: sSelect; source: Qt.resolvedUrl("sounds/select.wav") }
    Sfx { id: sBack; source: Qt.resolvedUrl("sounds/back.wav") }
    Sfx { id: sDialog; source: Qt.resolvedUrl("sounds/dialog.wav") }
    Sfx { id: sOn; source: Qt.resolvedUrl("sounds/toggle_on.wav") }
    Sfx { id: sOff; source: Qt.resolvedUrl("sounds/toggle_off.wav") }
    Sfx { id: sPrompt; source: Qt.resolvedUrl("sounds/prompt.wav") }
    Sfx { id: sError; source: Qt.resolvedUrl("sounds/error.wav") }
    Sfx { id: sSuccess; source: Qt.resolvedUrl("sounds/success.wav") }
    Sfx { id: sOpen; source: Qt.resolvedUrl("sounds/open.wav") }
    Sfx { id: sClose; source: Qt.resolvedUrl("sounds/close.wav") }
    Sfx { id: sLaunch; source: Qt.resolvedUrl("sounds/launch.wav") }

    Connections {
        target: LauraService

        function onStateChanged(): void {
            if (!root.active)
                return;
            if (LauraService.state === "on")
                root.sfx("toggle_on");
            else if (LauraService.state === "off")
                root.sfx("toggle_off");
            else if (LauraService.state === "error")
                root.sfx("error");
        }
    }

    // ================= Música ambiente =================
    // Suena en los menús (no con un juego abierto), se funde al entrar/salir y baja
    // cuando habla Laura. Si hay audio en ~/Música/Elysium/, se usa eso (aleatorio);
    // si no, la pieza propia (music/elysium-ambient.ogg, de sounds/music_gen.py).
    readonly property bool musicWanted: prefs.music && active && consoleShown && !playing
    property real musicLevel: musicWanted ? 1 : 0
    property var userTracks: []
    property int trackIdx: 0

    Behavior on musicLevel {
        NumberAnimation {
            duration: 1600
            easing.type: Easing.InOutSine
        }
    }

    onMusicWantedChanged: {
        if (musicWanted) {
            musicDir.running = true;
            if (music.playbackState !== MediaPlayer.PlayingState)
                music.play();
        }
    }
    onMusicLevelChanged: if (!musicWanted && musicLevel <= 0.001 && music.playbackState === MediaPlayer.PlayingState)
        music.pause()

    function nextTrack(): void {
        if (userTracks.length === 0)
            return;
        trackIdx = Math.floor(Math.random() * userTracks.length);
        music.source = "file://" + userTracks[trackIdx];
        music.play();
    }

    Process {
        id: musicDir

        command: ["sh", "-c", `find "${Quickshell.env("HOME")}/Música/Elysium" -maxdepth 2 -type f \\( -iname '*.ogg' -o -iname '*.mp3' -o -iname '*.flac' -o -iname '*.opus' -o -iname '*.m4a' -o -iname '*.wav' \\) 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter(l => l.length > 0);
                const changed = JSON.stringify(list) !== JSON.stringify(root.userTracks);
                root.userTracks = list;
                if (changed && list.length > 0)
                    root.nextTrack();
            }
        }
    }

    MediaPlayer {
        id: music

        source: Qt.resolvedUrl("music/elysium-ambient.ogg")
        loops: root.userTracks.length > 0 ? 1 : MediaPlayer.Infinite
        audioOutput: AudioOutput {
            device: mediaDevices.defaultAudioOutput
            volume: 0.32 * root.musicLevel * (Laura.active ? 0.25 : 1)

            Behavior on volume {
                NumberAnimation {
                    duration: 500
                }
            }
        }
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia && root.userTracks.length > 0)
            root.nextTrack()
    }

    function setMusic(on: bool): void {
        prefs.music = on;
        sfx(on ? "toggle_on" : "toggle_off");
    }

    // ================= Actualizaciones de Hookshot =================
    // check: {current, latest, published, sizeMB, update} · upd: estado de la actualización
    // en curso (archivo que escribe `elysium-hookshot run`, en segundo plano con systemd).
    readonly property string hsHelper: `${Quickshell.env("HOME")}/.local/bin/elysium-hookshot`
    property var hsCheck: ({})
    property bool hsChecking: false
    property real hsCheckedAt: 0
    property var upd: ({})
    readonly property bool updRunning: ["downloading", "building", "shaders"].indexOf(upd.state ?? "") >= 0 && updAlive
    property bool updAlive: false
    property bool updView: false      // pantalla de progreso abierta (si no, va en segundo plano)
    property bool updAsk: false       // diálogo «¿Actualizar?»
    property bool updAskedThisSession: false
    property var updAskGame: null
    property string _lastUpdState: ""

    function hookshotCheck(force: bool): void {
        if (hsChecking || updRunning || (!force && Date.now() - hsCheckedAt < 20 * 60 * 1000))
            return;
        hsChecking = true;
        hsCheckProc.running = true;
    }

    property bool hsSimulate: false   // prueba: la actualización corre en simulación

    function hookshotUpdate(simulate: bool): void {
        simulate = simulate || hsSimulate;
        if (updRunning)
            return;
        updAsk = false;
        updView = true;
        sfx("select");
        Quickshell.execDetached([hsHelper, "update"].concat(simulate ? ["--simulate"] : []));
        updAliveTimer.restart();
    }

    function hookshotCancel(): void {
        Quickshell.execDetached([hsHelper, "cancel"]);
        sfx("toggle_off");
    }

    Process {
        id: hsCheckProc

        command: [root.hsHelper, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    root.hsCheck = j;
                    // Nada más entrar: si hay versión nueva, preguntarlo una vez por sesión.
                    if (j.update && root.active && !root.playing && !root.updAskedThisSession) {
                        root.updAskedThisSession = true;
                        root.updAskGame = root.games.find(g => g.updates === "hookshot") ?? null;
                        root.updAsk = true;
                        root.sfx("prompt");
                    }
                } catch (e) {}
                root.hsChecking = false;
                root.hsCheckedAt = Date.now();
            }
        }
        onExited: root.hsChecking = false
    }

    FileView {
        id: updFile

        path: `${Quickshell.env("HOME")}/.cache/elysium/hookshot-update.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.upd = JSON.parse(text());
            } catch (e) {}
        }
    }

    // ¿Sigue vivo el servicio? (si el archivo dice «en curso» pero el servicio murió)
    Timer {
        id: updAliveTimer

        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: updAliveProc.running = true
    }

    Process {
        id: updAliveProc

        command: ["systemctl", "--user", "is-active", "-q", "elysium-hookshot-update"]
        onExited: code => root.updAlive = code === 0
    }

    onUpdChanged: {
        const st = upd.state ?? "";
        if (st === _lastUpdState)
            return;
        const prev = _lastUpdState;
        _lastUpdState = st;
        if (!prev)
            return;   // primera lectura al arrancar el shell: sin avisos
        if (st === "shaders") {
            sfx("prompt");
            Toaster.toast(qsTr("Precompilando shaders"), qsTr("Hookshot sigue en segundo plano: puedes usar el PC mientras tanto"), "deployed_code");
        } else if (st === "done") {
            sfx("success");
            Toaster.toast(qsTr("Hookshot actualizado"), qsTr("Versión %1 lista para jugar").arg(upd.latest ?? ""), "check_circle");
            hsCheck = Object.assign({}, hsCheck, { "update": false, "current": upd.latest ?? hsCheck.current });
            updAsk = false;
            if (!hsSimulate)
                hookshotCheck(true);
            hsSimulate = false;
        } else if (st === "error") {
            sfx("error");
            Toaster.toast(qsTr("La actualización de Hookshot falló"), upd.error ?? "", "error");
        }
    }

    function launch(g: var): void {
        runningGame = g;
        // Laura desactivada para este juego: se apaga y libera la gráfica.
        if (!lauraFor(g) && LauraService.state !== "off") {
            lauraStoppedForGame = true;
            LauraService.stop();
        }
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
                    root.setSink(hdmi);
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

    // Preferencias que se guardan: pantalla de juego y juegos sin Laura.
    QtObject {
        id: prefs

        property bool playOnTv: true
        property var lauraOff: []
        property bool sound: true
        property bool music: true
        property bool loaded: false

        onPlayOnTvChanged: if (loaded)
            prefsFile.save()
        onLauraOffChanged: if (loaded)
            prefsFile.save()
        onSoundChanged: if (loaded)
            prefsFile.save()
        onMusicChanged: if (loaded)
            prefsFile.save()
    }

    readonly property bool playOnTv: prefs.playOnTv
    readonly property bool musicOn: prefs.music

    FileView {
        id: prefsFile

        path: `${Quickshell.env("HOME")}/.local/state/caelestia/elysium.json`
        printErrors: false
        onLoaded: {
            try {
                const j = JSON.parse(text());
                prefs.playOnTv = j.playOnTv ?? true;
                prefs.lauraOff = j.lauraOff ?? [];
                prefs.sound = j.sound ?? true;
                prefs.music = j.music ?? true;
            } catch (e) {}
            prefs.loaded = true;
        }
        onLoadFailed: prefs.loaded = true

        function save(): void {
            setText(JSON.stringify({
                "playOnTv": prefs.playOnTv,
                "lauraOff": prefs.lauraOff,
                "sound": prefs.sound,
                "music": prefs.music
            }, null, 2));
        }
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
    property bool talkPending: false

    function talkToLaura(): void {
        // Apagada (la apagó Alberto, GameMode o el ahorro): arrancarla y hablar al estar lista.
        if (LauraService.state !== "on") {
            talkPending = true;
            LauraService.start();
            return;
        }
        if (Laura.state !== "idle" && Laura.state !== "speaking")
            return;
        Quickshell.execDetached(["python3", `${Quickshell.env("HOME")}/proyectos/LinuxRicing/assistant/laura-toggle`, "centro"]);
    }

    Connections {
        target: LauraService

        function onReady(): void {
            if (root.talkPending) {
                root.talkPending = false;
                root.talkToLaura();
            }
        }
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
        // Pantalla completa ya con el foco (pedida antes, mientras Elysium tenía el
        // teclado, Hyprland la ignoraba en el portátil).
        Quickshell.execDetached(["sh", "-c", `sleep 0.3; hyprctl clients -j | python3 -c 'import json,sys; sys.exit(0 if any(c["class"]=="${cls}" and not c["fullscreen"] for c in json.load(sys.stdin)) else 1)' && hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", window = "class:${cls}" })'`]);
    }

    // Cursor al centro-abajo del portátil: no tapa el juego y el foco se queda en él.
    // Cursor oculto tras 1 s quieto mientras se juega (las esquinas abren paneles de
    // Caelestia, así que no se «aparca» en una esquina). En la tele, además, se lleva
    // al portátil para que no quede encima del juego.
    property var prevCursorTimeout: null

    function hideIdleCursor(on: bool): void {
        if (on) {
            if (prevCursorTimeout === null)
                prevCursorTimeout = Hypr.options["cursor:inactive_timeout"] ?? 0; // qmllint disable missing-property
            Hypr.extras.applyOptions({ "cursor:inactive_timeout": 1 });
        } else if (prevCursorTimeout !== null) {
            Hypr.extras.applyOptions({ "cursor:inactive_timeout": prevCursorTimeout });
            prevCursorTimeout = null;
        }
    }

    onPlayingChanged: hideIdleCursor(playing)

    function parkCursor(): void {
        if (!onTv || !laptopScreen)
            return;
        const sc = laptopScreen;
        const x = sc.x + Math.round(sc.width / 2);
        const y = sc.y + sc.height - 80;
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
                root.restoreLauraAfterGame();
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

        // Estado interno (depuración).
        function debug(): string {
            return JSON.stringify({
                "active": root.active,
                "playing": root.playing,
                "summoned": root.summoned,
                "gameReady": root.gameReady,
                "consoleShown": root.consoleShown,
                "onTv": root.onTv,
                "playOnTv": root.playOnTv,
                "padGrab": root.padGrab,
                "consoleScreen": root.consoleScreen?.name ?? null,
                "laura": LauraService.state,
                "lauraStoppedForGame": root.lauraStoppedForGame,
                "music": ["parado", "sonando", "pausa"][music.playbackState] + " vol=" + music.audioOutput.volume.toFixed(2)
            });
        }

        function hookshotCheck(): void {
            root.hookshotCheck(true);
        }

        // Actualiza Hookshot (simulate=true: recorrido acelerado para probar la interfaz).
        function hookshotUpdate(simulate: bool): void {
            root.hookshotUpdate(simulate);
        }

        // Prueba: finge que hay versión nueva (la actualización correrá en simulación).
        function fakeUpdate(): void {
            root.hsSimulate = true;
            root.hsCheck = Object.assign({}, root.hsCheck, {
                "update": true,
                "latest": "v2.3.3",
                "published": "2026-11-20"
            });
            root.updAskGame = root.games[0];
            root.updAsk = true;
            root.sfx("prompt");
        }

        function music(on: bool): void {
            root.setMusic(on);
        }

        function sound(on: bool): void {
            prefs.sound = on;
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
