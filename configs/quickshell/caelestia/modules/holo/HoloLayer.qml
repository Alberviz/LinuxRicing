pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant
import "HoloPlacer.js" as HoloPlacer

// Capa de hologramas de Laura (una por pantalla; solo se enciende en la enfocada).
//
// Va en la capa Top, por DEBAJO de la píldora de Laura y de los portales de warp
// (ambos en Overlay): el velo oscurece el escritorio pero Laura y el agujero negro
// siguen encima.
//
// Los paneles viven en un ListModel propio (`vivos`, solo ids) y no directamente en
// HoloState.paneles: así cada panel conserva su delegado cuando cambia la escena y
// puede animar su salida antes de destruirse. Los datos de cada panel están en
// `datos[pid]` y su caja final en `pos[pid]` ({x, y, w, h, rot}).
//
// Nada corre en bucle: todas las animaciones son de una sola vez (aparecer, volar,
// barrido, salir). En reposo, coste cero.
PanelWindow {
    id: root

    required property ShellScreen modelData

    readonly property bool enfocada: Hypr.focusedMonitor?.name === modelData.name
    readonly property bool hayEscena: HoloState.activo && enfocada
    // Sigue en pie mientras corren las animaciones de salida
    property bool shown: false
    property real veil: 0

    property var datos: ({})
    property var pos: ({})
    property var reg: ({})
    property int zTop: 10
    // Paneles vivos (también los que se están yendo): los hilos se cuelgan de aquí para
    // poder retraerse mientras su visor se va.
    readonly property ListModel modelo: vivos
    // Cascada de nacimientos: cuándo y con qué retraso nació el último
    property real ultimoNacer: 0
    property int ultimoRetraso: 0

    // Centro de la píldora de Laura (LauraOverlay: abajo, centrada, margen extraLarge*2)
    readonly property point origen: Qt.point(width / 2, height - (screen ? contentItem.Tokens.padding.extraLarge * 2 : 48) - 26)

    screen: modelData
    visible: shown
    color: "transparent"

    WlrLayershell.namespace: "caelestia-holo"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    contentItem.Config.screen: screen ? screen.name : ""
    contentItem.Tokens.screen: screen ? screen.name : ""

    // ---------------------------------------------------------------- geometría

    function cajaLista(nItems: int, conVisores: bool): var {
        const w = Math.round(Math.min(500, Math.max(380, width * 0.27)));
        const h = Math.round(HoloGeo.cabecera + HoloGeo.listaArriba + HoloGeo.fila * Math.max(1, nItems) + HoloGeo.listaPie);
        const x = conVisores ? Math.round(width * 0.055) : Math.round((width - w) / 2);
        const y = Math.max(48, Math.round((height - h) / 2 - height * 0.05));
        return {
            x: x,
            y: y,
            w: w,
            h: h,
            rot: 0
        };
    }

    function cajaVisor(panel, ocupados): var {
        const sz = HoloPlacer.size(panel, width, height);
        // Si no hay hueco a tamaño completo, se encoge (nunca se monta sobre otro panel)
        let w = sz.w, h = sz.h, p = null;
        for (const f of [1, 0.85, 0.72, 0.6]) {
            w = Math.round(sz.w * f);
            h = Math.round(sz.h * f);
            p = HoloPlacer.place(width, height, ocupados, w, h);
            if (p.libre)
                break;
        }
        return {
            x: p.x,
            y: p.y,
            w: w,
            h: h,
            rot: p.rot
        };
    }

    function idsVivos(): var {
        const r = [];
        for (let i = 0; i < vivos.count; i++)
            r.push(vivos.get(i).pid);
        return r;
    }

    // Reconciliar la escena del daemon con los paneles vivos
    function sync(): void {
        const ps = (enfocada ? HoloState.paneles : []) || [];
        const ids = ps.map(p => p.id);

        const d = Object.assign({}, datos);
        for (const p of ps)
            d[p.id] = p;
        datos = d;

        if (ps.length > 0) {
            shown = true;
            veilOut.stop();
            if (veil < 1 && !veilIn.running)
                veilIn.start();
        }

        // La ventana acaba de mostrarse y aún no tiene su tamaño real (arranca en 500×500 hasta
        // que el compositor la configura): colocar ahora daría cajas absurdas, y cada panel se
        // coloca una sola vez. Se reintenta en cuanto mida lo que la pantalla.
        if (ps.length > 0 && screen && (width < screen.width * 0.9 || height < screen.height * 0.9)) {
            reintento.restart();
            return;
        }

        // Salidas (en cascada si se van varios a la vez); y al revés: si vuelven a pedir uno
        // que se estaba yendo, da media vuelta en vez de desaparecer
        let k = 0;
        for (const pid of idsVivos()) {
            const r = reg[pid];
            if (!r)
                continue;
            if (ids.indexOf(pid) < 0 && !r.saliendo)
                r.salir(Math.min(HoloGeo.maxEscalon, (k++) * HoloGeo.escalonSalida));
            else if (ids.indexOf(pid) >= 0 && r.saliendo)
                r.volver();
        }

        // Cajas: la lista se recalcula siempre (cambia con los items y con los visores);
        // cada visor se coloca UNA vez, al aparecer, esquivando lo que ya hay.
        const np = Object.assign({}, pos);
        const conVisores = ps.some(p => p.kind === "visor");
        if (ids.indexOf("lista") >= 0)
            np["lista"] = cajaLista((HoloState.items || []).length, conVisores);
        for (const p of ps) {
            if ((p.kind !== "visor" && p.kind !== "confirmar") || np[p.id])
                continue;
            const ocupados = [];
            for (const id of ids)
                if (np[id] && id !== p.id)
                    ocupados.push(np[id]);
            np[p.id] = cajaVisor(p, ocupados);
        }
        pos = np;

        // Entradas
        const vivosAhora = idsVivos();
        for (const p of ps)
            if (vivosAhora.indexOf(p.id) < 0)
                vivos.append({
                    pid: p.id
                });

        // Sin escena: el velo se apaga a la vez que los paneles se van (no después)
        if (ps.length === 0)
            apagar();
    }

    // Retraso de nacimiento: los paneles que llegan juntos (en el mismo instante o casi)
    // salen en cascada en vez de a la vez; uno suelto nace sin esperar.
    function turnoNacer(): int {
        const ahora = Date.now();
        const pendiente = ultimoNacer + ultimoRetraso - ahora;
        const r = pendiente > -60 ? Math.min(HoloGeo.maxEscalon, Math.max(0, pendiente) + HoloGeo.escalonPanel) : 0;
        ultimoNacer = ahora;
        ultimoRetraso = r;
        return r;
    }

    function quitar(pid: string): void {
        for (let i = 0; i < vivos.count; i++) {
            if (vivos.get(i).pid === pid) {
                vivos.remove(i);
                break;
            }
        }
        const np = Object.assign({}, pos);
        delete np[pid];
        pos = np;
        const r = Object.assign({}, reg);
        delete r[pid];
        reg = r;
        if (vivos.count === 0 && !HoloState.activo)
            apagar();
    }

    function apagar(): void {
        if (!shown || veilOut.running)
            return;
        veilIn.stop();
        // Velo ya apagado y nada animándose: cerrar del todo sin esperar
        if (veil <= 0.001 && vivos.count === 0) {
            terminar();
            return;
        }
        veilOut.start();
    }

    function terminar(): void {
        if (HoloState.activo && enfocada)
            return;
        // Aún hay paneles volviendo a la píldora: quitar() llamará otra vez al acabar
        if (vivos.count > 0)
            return;
        shown = false;
        datos = ({});
        pos = ({});
    }

    // Un panel arrastrado y soltado se queda donde lo dejas
    function mover(pid: string, x: real, y: real): void {
        if (!pos[pid])
            return;
        const np = Object.assign({}, pos);
        np[pid] = Object.assign({}, np[pid], {
            x: x,
            y: y
        });
        pos = np;
    }

    function alFrente(pid: string): void {
        if (reg[pid])
            reg[pid].z = ++zTop;
    }

    function registrar(pid: string, item: Item): void {
        const r = Object.assign({}, reg);
        r[pid] = item;
        reg = r;
    }

    // Fila n de la lista: centro vertical en coordenadas de pantalla (para los hilos)
    function filaY(n: int): real {
        const l = pos["lista"];
        if (!l)
            return 0;
        return l.y + HoloGeo.cabecera + HoloGeo.listaArriba + HoloGeo.fila * (n - 1) + HoloGeo.fila / 2;
    }

    onEnfocadaChanged: sync()

    Connections {
        function onPanelesChanged(): void {
            root.sync();
        }
        // El daemon manda `items` antes que `paneles`: reconciliar al final del evento (si no,
        // al cerrar, la lista se encogería a una fila mientras se va)
        function onItemsChanged(): void {
            Qt.callLater(root.sync);
        }
        function onSeleccionadoChanged(): void {
            if (HoloState.seleccionado > 0)
                root.alFrente("v" + HoloState.seleccionado);
        }
        function onSent(pid: string): void {
            if (root.reg[pid])
                root.reg[pid].enviar();
        }
        // Un plan de archivos se ha ejecutado: los visores afectados se van (borrar → papelera)
        function onFx(ev: var): void {
            if (!root.enfocada)
                return;
            for (const id of (ev.ids || [])) {
                const p = root.reg[id];
                if (!p)
                    continue;
                if (ev.fx === "borrar")
                    p.desintegrar();
                else
                    p.salir(0);
            }
            if (ev.fx === "borrar")
                papelera.pulsar();
        }

        target: HoloState
    }

    ListModel {
        id: vivos
    }

    Timer {
        id: reintento

        interval: 40
        onTriggered: root.sync()
    }

    NumberAnimation {
        id: veilIn

        target: root
        property: "veil"
        to: 1
        duration: HoloGeo.tMedio + 40
        easing.type: HoloGeo.curvaEntra
        onStarted: sweep.start()
    }

    SequentialAnimation {
        id: veilOut

        // Breve espera para que los paneles empiecen a irse antes de que caiga el telón
        PauseAnimation {
            duration: 100
        }
        NumberAnimation {
            target: root
            property: "veil"
            to: 0
            duration: HoloGeo.tMedio + 60
            easing.type: Easing.InOutQuad
        }
        ScriptAction {
            script: root.terminar()
        }
    }

    Item {
        id: container

        anchors.fill: parent
        focus: root.shown
        Keys.onEscapePressed: HoloState.cerrarTodo()

        // ------------------------------------------------------------ velo de foco
        Item {
            id: veilItem

            anchors.fill: parent
            opacity: root.veil

            // Oscuro con un punto de color del tema (no negro puro)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(Colours.palette.m3surface.r * 0.35, Colours.palette.m3surface.g * 0.35, Colours.palette.m3surface.b * 0.35, 0.74)
            }

            // Resplandor que sube desde la píldora de Laura
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: root.width / 2
                        centerY: root.height * 1.08
                        centerRadius: root.height * 0.72
                        focalX: centerX
                        focalY: centerY

                        GradientStop {
                            position: 0
                            color: Qt.alpha(Colours.palette.m3primary, 0.30)
                        }
                        GradientStop {
                            position: 0.45
                            color: Qt.alpha(Colours.palette.m3primary, 0.10)
                        }
                        GradientStop {
                            position: 1
                            color: "transparent"
                        }
                    }

                    PathLine {
                        x: root.width
                        y: 0
                    }
                    PathLine {
                        x: root.width
                        y: root.height
                    }
                    PathLine {
                        x: 0
                        y: root.height
                    }
                    PathLine {
                        x: 0
                        y: 0
                    }
                }
            }

            // Malla de puntos: eco de las estrellas del sistema solar
            Image {
                anchors.fill: parent
                fillMode: Image.Tile
                source: Qt.resolvedUrl("assets/dots.png")
                opacity: 0.16
                smooth: false
            }

            // Viñeta: apaga la malla y el color hacia los bordes
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: root.width / 2
                        centerY: root.height * 0.46
                        centerRadius: Math.max(root.width, root.height) * 0.72
                        focalX: centerX
                        focalY: centerY

                        GradientStop {
                            position: 0.35
                            color: "transparent"
                        }
                        GradientStop {
                            position: 1
                            color: Qt.rgba(0, 0, 0, 0.62)
                        }
                    }

                    PathLine {
                        x: root.width
                        y: 0
                    }
                    PathLine {
                        x: root.width
                        y: root.height
                    }
                    PathLine {
                        x: 0
                        y: root.height
                    }
                    PathLine {
                        x: 0
                        y: 0
                    }
                }
            }

            // Bloquea los clics hacia lo de detrás; un clic en el vacío no cierra nada
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }
        }

        // Barrido de escaneo: una línea de luz recorre la pantalla al encenderse la escena
        Item {
            id: sweepLine

            property real p: 0

            width: parent.width
            height: 90
            y: -height + (root.height + height) * p
            opacity: p > 0 && p < 1 ? 1 : 0
            visible: opacity > 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: line.top
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colours.palette.m3primary, 0.07)
                    }
                }
            }
            Rectangle {
                id: line

                anchors.bottom: parent.bottom
                width: parent.width
                height: 1.5
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(Colours.palette.m3primary, 0.55)
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }

            NumberAnimation on p {
                id: sweep

                running: false
                from: 0
                to: 1
                duration: 900
                easing.type: Easing.InOutSine
            }
        }

        // ------------------------------------------------------------ hilos fila → visor
        HoloLinks {
            anchors.fill: parent
            capa: root
            opacity: root.veil
        }

        // Papelera: aparece un instante en la esquina cuando se borra algo (one-shot)
        Item {
            id: papelera

            property real p: 0
            // Golpe al «tragarse» lo que cae (coincide con la llegada de la desintegración)
            property real golpe: 0

            function pulsar(): void {
                pulso.restart();
            }

            x: root.width - 90
            y: root.height - 90
            width: 44
            height: 44
            z: 1
            opacity: p
            visible: p > 0.001
            scale: 0.8 + 0.2 * p + 0.18 * golpe

            Rectangle {
                anchors.fill: parent
                radius: 22
                color: Qt.alpha(Colours.palette.m3error, 0.18)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3error, 0.7)
            }
            MaterialIcon {
                anchors.centerIn: parent
                text: "delete"
                fontStyle: Tokens.font.icon.small
                color: Colours.palette.m3error
            }
            SequentialAnimation {
                id: pulso

                NumberAnimation {
                    target: papelera
                    property: "p"
                    to: 1
                    duration: HoloGeo.tRapido
                    easing.type: HoloGeo.curvaEntra
                }
                // Lo que se borra tarda ~0,5 s en caer: la papelera lo espera abierta…
                PauseAnimation {
                    duration: 300
                }
                // …y da un golpe seco al recibirlo
                NumberAnimation {
                    target: papelera
                    property: "golpe"
                    to: 1
                    duration: 90
                    easing.type: HoloGeo.curvaEntra
                }
                NumberAnimation {
                    target: papelera
                    property: "golpe"
                    to: 0
                    duration: HoloGeo.tMedio
                    easing.type: Easing.OutBack
                }
                PauseAnimation {
                    duration: 160
                }
                NumberAnimation {
                    target: papelera
                    property: "p"
                    to: 0
                    duration: HoloGeo.tMedio
                    easing.type: HoloGeo.curvaSale
                }
            }
        }

        // ------------------------------------------------------------ paneles
        Repeater {
            model: vivos

            HoloPanel {
                capa: root
            }
        }
    }
}
