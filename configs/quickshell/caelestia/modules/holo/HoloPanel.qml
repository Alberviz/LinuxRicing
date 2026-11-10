pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Chasis de un holograma: cristal oscuro, borde y halo del color del tema, líneas
// de escaneo, cabecera y el contenido según el tipo.
//
// Coreografía (todo de una sola vez, nada en bucle):
//   nacer   — un rayo sale de la píldora de Laura hacia el destino; el panel vuela
//             detrás desde la píldora (escala 0,12 → 1, con un giro leve), parpadea
//             como un holograma al llegar y una línea de luz lo recorre de arriba abajo.
//   salir   — vuelve a la píldora encogiéndose (en cascada si se van varios).
//   enviar  — se estira y sube hacia el agujero negro de warp (borde superior).
// El halo es un par de bordes translúcidos, sin blur ni sombras.
Item {
    id: root

    required property string pid
    required property var capa

    readonly property var panel: capa.datos[pid] ?? null
    readonly property var caja: capa.pos[pid] ?? ({
            x: capa.origen.x - 150,
            y: capa.origen.y - 100,
            w: 300,
            h: 200,
            rot: 0
        })
    readonly property bool esVisor: panel?.kind === "visor"
    readonly property bool esLista: panel?.kind === "lista"
    readonly property bool esConfirmar: panel?.kind === "confirmar"
    readonly property var payload: panel?.payload ?? ({})
    readonly property var item: esVisor ? HoloState.item(panel.item_n) : null
    readonly property bool seleccionado: esVisor && panel.item_n === HoloState.seleccionado
    readonly property bool enviado: item?.enviado ?? false

    // 0 = en la píldora, 1 = en su sitio
    property real vuelo: 0
    // 0 = en su sitio, 1 = tragado por el agujero negro
    property real sube: 0
    // 0 = en su sitio, 1 = tragado por la papelera (esquina inferior derecha)
    property real cae: 0
    property real escala: 0.12
    // Ya está en su sitio (fin del vuelo): desde aquí se puede tocar, arrastrar y recolocar
    property bool llegado: false
    property bool saliendo: false
    property bool enviando: false
    property real barrido: -1
    // Retraso del nacimiento cuando nacen varios a la vez (lo reparte la capa)
    property int retrasoNacer: 0
    // 0..1: levantado al arrastrar (un pelín más grande y con más halo)
    property real alzado: arrastre.active ? 1 : 0
    // 0..1..0: destello del halo al pasar a ser «esa»
    property real destello: 0
    readonly property bool resaltado: esVisor && item !== null && HoloState.resaltado === item.n
    readonly property bool cercaArriba: arrastre.active && esVisor && y < 90
    // Recuento de la lista congelado mientras se va (el daemon vacía `items` al cerrar)
    property int nArchivos: 0

    // El daemon manda `items` antes que `paneles`: se mira al final del evento, cuando ya
    // se sabe si este panel se está yendo
    function contar(): void {
        if (!saliendo)
            nArchivos = (HoloState.items || []).length;
    }

    Connections {
        function onItemsChanged(): void {
            Qt.callLater(root.contar);
        }

        target: HoloState
    }
    // 0 = reposo, 0,5 = señalado (hover propio o de su fila), 1 = «esa» o a punto de enviarse.
    // Un único número animado para halo y borde: estados que se cruzan sin saltos.
    property real realce: (seleccionado || cercaArriba) ? 1 : (resaltado || hover.hovered) ? 0.5 : 0

    Behavior on realce {
        NumberAnimation {
            duration: HoloGeo.tRapido
            easing.type: HoloGeo.curvaFundido
        }
    }
    readonly property color prim: cercaArriba ? Colours.palette.m3tertiary : (esConfirmar && payload.accion === "borrar") ? Colours.palette.m3error : Colours.palette.m3primary
    readonly property string iconoConfirmar: ({
            borrar: "delete",
            mover: "drive_file_move",
            renombrar: "edit",
            crear_carpeta: "create_new_folder"
        })[payload.accion] ?? "help"

    function baseX(): real {
        const o = capa.origen.x - width / 2;
        return o + (caja.x - o) * vuelo;
    }
    function baseY(): real {
        const o = capa.origen.y - height / 2;
        return o + (caja.y - o) * vuelo;
    }
    function fijarPosicion(): void {
        x = Qt.binding(() => root.baseX() + (root.capa.width / 2 - root.width / 2 - root.baseX()) * root.sube);
        y = Qt.binding(() => root.baseY() + (-root.height * 1.1 - root.baseY()) * root.sube);
    }

    // Corta lo que estuviera en marcha sin dejar restos (la línea del barrido congelada,
    // el parpadeo a medias…): la siguiente animación parte de los valores actuales.
    function cortar(): void {
        nacer.stop();
        rayoItem.cortar();
        barrido = -1;
    }
    function salir(retraso: int): void {
        if (saliendo || enviando)
            return;
        saliendo = true;
        llegado = false;
        cortar();
        salida.retraso = retraso;
        salida.start();
    }
    function desintegrar(): void {
        if ((saliendo && !salida.running) || enviando)
            return;
        saliendo = true;
        llegado = false;
        cortar();
        salida.stop();
        desint.start();
    }
    // Lo vuelven a pedir mientras se iba: da media vuelta desde donde esté, sin recrearse
    function volver(): void {
        if (!saliendo || enviando)
            return;
        salida.stop();
        desint.stop();
        saliendo = false;
        regreso.start();
    }
    // Cerrar con la ✕ o clic derecho: en una confirmación equivale a cancelar el plan
    function cerrarPanel(): void {
        if (esConfirmar)
            HoloState.cancelar(payload.plan);
        else
            HoloState.cerrar(pid);
    }
    function enviar(): void {
        if (enviando || saliendo)
            return;
        enviando = true;
        llegado = false;
        cortar();
        envio.start();
    }
    function soltado(): void {
        if (cercaArriba && item) {
            HoloState.enviar(item.n);
            enviar();
            return;
        }
        // Se queda donde lo sueltas: esa pasa a ser su caja (vuelo = 1, así baseX() = x)
        capa.mover(pid, x, y);
        fijarPosicion();
    }

    width: caja.w
    height: caja.h
    z: 1
    opacity: 0
    scale: escala * (1 + 0.018 * alzado + 0.01 * destello)
    rotation: caja.rot * vuelo
    transformOrigin: Item.Center
    transform: [
        Scale {
            origin.x: root.width / 2
            origin.y: 0
            xScale: 1 - 0.72 * root.sube
            yScale: 1 + 0.4 * root.sube
        },
        Translate {
            x: (root.capa.width - 68 - (root.x + root.width / 2)) * root.cae
            y: (root.capa.height - 68 - (root.y + root.height / 2)) * root.cae
        }
    ]

    Component.onCompleted: {
        capa.registrar(pid, root);
        capa.alFrente(pid);
        fijarPosicion();
        retrasoNacer = capa.turnoNacer();
        nArchivos = (HoloState.items || []).length;
        nacer.start();
    }

    Component.onDestruction: {
        if (esVisor && HoloState.resaltado === panel?.item_n)
            HoloState.resaltado = -1;
    }

    onSeleccionadoChanged: {
        if (seleccionado && llegado && !saliendo)
            ping.restart();
    }

    Behavior on alzado {
        NumberAnimation {
            duration: HoloGeo.tRapido
            easing.type: HoloGeo.curvaEntra
        }
    }

    // La lista se aparta cuando se abren visores: deslizarse, no saltar
    Behavior on x {
        enabled: root.llegado && !arrastre.active

        Anim {
            type: Anim.DefaultSpatial
        }
    }
    Behavior on y {
        enabled: root.llegado && !arrastre.active

        Anim {
            type: Anim.DefaultSpatial
        }
    }
    Behavior on height {
        enabled: root.llegado

        Anim {
            type: Anim.DefaultSpatial
        }
    }

    // ------------------------------------------------------------------ animaciones
    // Todas de una sola vez. Las que pueden pisarse se cortan con cortar() antes de
    // arrancar la siguiente, que parte siempre de los valores actuales (sin «from»).

    SequentialAnimation {
        id: nacer

        // Si nacen varios a la vez, salen en cascada (el rayo de cada uno, uno tras otro)
        PauseAnimation {
            duration: root.retrasoNacer
        }
        ScriptAction {
            script: rayoItem.start()
        }
        PauseAnimation {
            duration: 60
        }
        // Vuelo: posición y escala comparten duración para que el panel llegue entero a la
        // vez; el rebote es mínimo (un asentarse, no un muelle).
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "vuelo"
                to: 1
                duration: HoloGeo.tVuelo
                easing.type: HoloGeo.curvaEntra
            }
            NumberAnimation {
                target: root
                property: "escala"
                to: 1
                duration: HoloGeo.tVuelo
                easing.type: Easing.OutBack
                easing.overshoot: 0.9
            }
            NumberAnimation {
                target: root
                property: "opacity"
                to: 0.9
                duration: HoloGeo.tRapido
                easing.type: HoloGeo.curvaFundido
            }
        }
        // En su sitio: ya responde (arrastrar, clic) y se recoloca deslizándose
        ScriptAction {
            script: root.llegado = true
        }
        // Parpadeo de holograma al «enfocar» (la firma visual, corta: ~125 ms)
        NumberAnimation {
            target: root
            property: "opacity"
            to: 0.55
            duration: 40
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: 50
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: 0.8
            duration: 35
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 1
                duration: 80
            }
            NumberAnimation {
                target: root
                property: "barrido"
                from: 0
                to: 1
                duration: HoloGeo.tBarrido
                easing.type: Easing.InOutSine
            }
        }
        ScriptAction {
            script: root.barrido = -1
        }
    }

    // Vuelve a la píldora: más rápido que la entrada y acelerando (se va, no llega)
    SequentialAnimation {
        id: salida

        property int retraso: 0

        PauseAnimation {
            duration: salida.retraso
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "vuelo"
                to: 0
                duration: HoloGeo.tSalida
                easing.type: HoloGeo.curvaSale
            }
            NumberAnimation {
                target: root
                property: "escala"
                to: 0.1
                duration: HoloGeo.tSalida
                easing.type: HoloGeo.curvaSale
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: HoloGeo.tSalida * 0.4
                }
                NumberAnimation {
                    target: root
                    property: "opacity"
                    to: 0
                    duration: HoloGeo.tSalida * 0.6
                }
            }
        }
        ScriptAction {
            script: root.capa.quitar(root.pid)
        }
    }

    // A la papelera: un chisporroteo breve (se «desintegra») y cae encogiéndose
    SequentialAnimation {
        id: desint

        NumberAnimation {
            target: root
            property: "opacity"
            to: 0.45
            duration: 45
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: 0.95
            duration: 45
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "cae"
                to: 1
                duration: HoloGeo.tLento
                easing.type: HoloGeo.curvaSale
            }
            NumberAnimation {
                target: root
                property: "escala"
                to: 0.05
                duration: HoloGeo.tLento
                easing.type: HoloGeo.curvaSale
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: HoloGeo.tLento * 0.45
                }
                NumberAnimation {
                    target: root
                    property: "opacity"
                    to: 0
                    duration: HoloGeo.tLento * 0.55
                }
            }
        }
        ScriptAction {
            script: root.capa.quitar(root.pid)
        }
    }

    SequentialAnimation {
        id: envio

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "sube"
                to: 1
                duration: 460
                easing.type: HoloGeo.curvaSale
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 240
                }
                NumberAnimation {
                    target: root
                    property: "opacity"
                    to: 0
                    duration: 220
                }
            }
        }
        ScriptAction {
            script: {
                // El visor ya está en el móvil: se cierra en el daemon (la lista
                // conserva la fila marcada «→ móvil ✓»).
                root.saliendo = true;
                HoloState.cerrar(root.pid);
                root.capa.quitar(root.pid);
            }
        }
    }

    // Media vuelta: lo vuelven a pedir mientras se iba
    SequentialAnimation {
        id: regreso

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "vuelo"
                to: 1
                duration: HoloGeo.tMedio
                easing.type: HoloGeo.curvaEntra
            }
            NumberAnimation {
                target: root
                property: "escala"
                to: 1
                duration: HoloGeo.tMedio
                easing.type: HoloGeo.curvaEntra
            }
            NumberAnimation {
                target: root
                property: "cae"
                to: 0
                duration: HoloGeo.tMedio
                easing.type: HoloGeo.curvaEntra
            }
            NumberAnimation {
                target: root
                property: "opacity"
                to: 1
                duration: HoloGeo.tRapido
                easing.type: HoloGeo.curvaFundido
            }
        }
        ScriptAction {
            script: root.llegado = true
        }
    }

    // «Esa»: un destello corto del halo y un respiro de escala confirman la selección
    SequentialAnimation {
        id: ping

        NumberAnimation {
            target: root
            property: "destello"
            to: 1
            duration: HoloGeo.tMicro
            easing.type: HoloGeo.curvaFundido
        }
        NumberAnimation {
            target: root
            property: "destello"
            to: 0
            duration: HoloGeo.tLento
            easing.type: Easing.InOutSine
        }
    }

    // ------------------------------------------------------------------ rayo de nacimiento

    // Un pulso de luz viaja de la píldora al destino: la punta avanza y la cola la sigue,
    // así el rayo «entra» en el panel en vez de quedarse pintado y fundirse entero.
    Item {
        id: rayoItem

        readonly property real dx: root.caja.x + root.caja.w / 2 - root.capa.origen.x
        readonly property real dy: root.caja.y + root.caja.h / 2 - root.capa.origen.y
        readonly property real largo: Math.hypot(dx, dy)
        property real crece: 0
        property real cola: 0

        function start(): void {
            rayoAnim.restart();
        }
        function cortar(): void {
            rayoAnim.stop();
            opacity = 0;
        }

        parent: root.parent
        x: root.capa.origen.x
        y: root.capa.origen.y
        z: 0
        width: 0
        height: 0
        visible: opacity > 0
        rotation: Math.atan2(-dx, dy) * 180 / Math.PI
        transformOrigin: Item.TopLeft
        opacity: 0

        // Halo ancho y núcleo fino
        Rectangle {
            x: -3
            y: rayoItem.largo * rayoItem.cola
            width: 6
            height: Math.max(0, rayoItem.largo * (rayoItem.crece - rayoItem.cola))
            radius: 3
            opacity: 0.35
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colours.palette.m3primary, 0.0)
                }
                GradientStop {
                    position: 1
                    color: Colours.palette.m3primary
                }
            }
        }
        Rectangle {
            x: -0.75
            y: rayoItem.largo * rayoItem.cola
            width: 1.5
            height: Math.max(0, rayoItem.largo * (rayoItem.crece - rayoItem.cola))
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colours.palette.m3primary, 0.2)
                }
                GradientStop {
                    position: 1
                    color: Qt.lighter(Colours.palette.m3primary, 1.25)
                }
            }
        }
        // Chispa en la punta
        Rectangle {
            x: -4
            y: rayoItem.largo * rayoItem.crece - 4
            width: 8
            height: 8
            radius: 4
            color: Qt.lighter(Colours.palette.m3primary, 1.3)
        }

        SequentialAnimation {
            id: rayoAnim

            PropertyAction {
                target: rayoItem
                property: "cola"
                value: 0
            }
            PropertyAction {
                target: rayoItem
                property: "opacity"
                value: 1
            }
            ParallelAnimation {
                NumberAnimation {
                    target: rayoItem
                    property: "crece"
                    from: 0
                    to: 1
                    duration: 230
                    easing.type: HoloGeo.curvaEntra
                }
                SequentialAnimation {
                    PauseAnimation {
                        duration: 110
                    }
                    NumberAnimation {
                        target: rayoItem
                        property: "cola"
                        to: 1
                        duration: 330
                        easing.type: HoloGeo.curvaCambia
                    }
                }
                SequentialAnimation {
                    PauseAnimation {
                        duration: 300
                    }
                    NumberAnimation {
                        target: rayoItem
                        property: "opacity"
                        to: 0
                        duration: 140
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------ halo

    Rectangle {
        anchors.fill: cuerpo
        anchors.margins: -12
        radius: cuerpo.radius + 12
        color: "transparent"
        border.width: 7
        border.color: Qt.alpha(root.prim, 0.045 + 0.055 * root.realce + 0.07 * root.destello + 0.03 * root.alzado)
    }
    Rectangle {
        anchors.fill: cuerpo
        anchors.margins: -5
        radius: cuerpo.radius + 5
        color: "transparent"
        border.width: 5
        border.color: Qt.alpha(root.prim, 0.12 + 0.12 * root.realce + 0.16 * root.destello + 0.05 * root.alzado)
    }

    // ------------------------------------------------------------------ cuerpo

    StyledClippingRect {
        id: cuerpo

        anchors.fill: parent
        radius: Tokens.rounding.large
        color: "transparent"

        // Cristal
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.90)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.93)
                }
            }
        }

        // Reflejo superior teñido
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.height * 0.32
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(root.prim, 0.13)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }

        // Cabecera
        Item {
            id: cabecera

            anchors.left: parent.left
            anchors.right: parent.right
            height: HoloGeo.cabecera

            Row {
                id: titulo

                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                // Número del archivo (visor) o icono (lista)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.esVisor && root.panel?.item_n
                    width: 22
                    height: 22
                    radius: 11
                    color: root.prim

                    StyledText {
                        anchors.centerIn: parent
                        text: root.panel?.item_n ?? ""
                        color: Colours.palette.m3onPrimary
                        font.family: Tokens.font.label.small.family
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                }
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.esVisor || !root.panel?.item_n
                    text: root.panel?.icono ? root.panel.icono : root.esConfirmar ? root.iconoConfirmar : ((root.panel?.titulo ?? "").startsWith("«") ? "search" : "folder_open")
                    color: root.prim
                    fill: 1
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, root.width - meta.implicitWidth - 120)
                    text: (root.panel?.titulo ?? "").toUpperCase()
                    color: root.prim
                    font.family: Tokens.font.label.small.family
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.4
                    elide: Text.ElideMiddle
                }
            }

            StyledText {
                id: meta

                anchors.right: cerrar.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: root.enviado ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                opacity: root.enviado ? 1 : 0.75
                font.family: Tokens.font.label.small.family
                font.pixelSize: 11
                font.letterSpacing: 0.4
                text: {
                    if (root.esConfirmar)
                        return "¿confirmas?";
                    if (root.enviado)
                        return "→ móvil ✓";
                    if (root.esLista) {
                        const n = root.nArchivos;
                        return n === 1 ? "1 archivo" : n + " archivos";
                    }
                    const p = root.payload;
                    switch (p.tipo) {
                    case "imagen":
                        return p.w > 0 ? p.w + "×" + p.h : "imagen";
                    case "pdf":
                        return "pág " + p.pagina + "/" + p.paginas;
                    case "texto":
                        return p.formato === "markdown" ? "markdown" : "texto";
                    case "video":
                        return "vídeo";
                    case "audio":
                        return "audio";
                    case "agenda": {
                        const n = (p.dias ?? []).reduce((a, d) => a + (d.eventos ?? []).length, 0);
                        return n === 1 ? "1 evento" : n + " eventos";
                    }
                    case "correo": {
                        const n = (p.items ?? []).length;
                        return n === 1 ? "1 correo" : n + " correos";
                    }
                    case "tareas": {
                        const n = (p.items ?? []).length;
                        return n === 1 ? "1 tarea" : n + " tareas";
                    }
                    default:
                        return p.mime || "";
                    }
                }
            }

            // Cerrar
            Item {
                id: cerrar

                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28

                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: Qt.alpha(Colours.palette.m3onSurface, cerrarMa.pressed ? 0.2 : cerrarMa.containsMouse ? 0.12 : 0)
                    scale: cerrarMa.pressed ? 0.9 : 1

                    Behavior on color {
                        ColorAnimation {
                            duration: HoloGeo.tMicro
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: HoloGeo.tMicro
                            easing.type: HoloGeo.curvaEntra
                        }
                    }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    color: cerrarMa.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
                MouseArea {
                    id: cerrarMa

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cerrarPanel()
                }
            }

            // Arrastrar por la cabecera; soltar arriba = enviar al móvil
            DragHandler {
                id: arrastre

                target: root
                enabled: root.llegado || active
                cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onActiveChanged: {
                    if (active)
                        root.capa.alFrente(root.pid);
                    else
                        root.soltado();
                }
            }
        }

        // Filo de la cabecera: luz que se apaga hacia la derecha
        Rectangle {
            anchors.top: cabecera.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.alpha(root.prim, 0.55)
                }
                GradientStop {
                    position: 0.7
                    color: Qt.alpha(root.prim, 0.08)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }

        // Contenido por tipo
        Loader {
            id: contenido

            readonly property string fichero: {
                if (root.esConfirmar)
                    return "HoloConfirm.qml";
                if (root.esLista)
                    return "HoloList.qml";
                switch (root.payload.tipo) {
                case "imagen":
                    return "HoloImage.qml";
                case "pdf":
                    return "HoloPdf.qml";
                case "video":
                case "audio":
                    return "HoloMedia.qml";
                case "texto":
                    return "HoloText.qml";
                case "agenda":
                    return "HoloAgenda.qml";
                case "correo":
                case "tareas":
                    return "HoloCorreo.qml";
                default:
                    return "HoloOther.qml";
                }
            }

            anchors.fill: parent
            anchors.topMargin: HoloGeo.cabecera + 1
            asynchronous: false

            Component.onCompleted: {
                if (root.panel)
                    setSource(Qt.resolvedUrl(fichero), {
                        panel: root.panel
                    });
            }
            onLoaded: item.panel = Qt.binding(() => root.panel ?? item.panel)
        }

        StyledText {
            anchors.centerIn: parent
            visible: contenido.status === Loader.Error
            text: root.panel?.titulo ?? ""
            color: Colours.palette.m3onSurfaceVariant
        }

        // Líneas de escaneo
        Image {
            anchors.fill: parent
            fillMode: Image.Tile
            source: Qt.resolvedUrl("assets/scan.png")
            smooth: false
            opacity: 0.8
        }

        // Línea de luz que recorre el panel al materializarse
        Item {
            visible: root.barrido >= 0
            width: parent.width
            height: 60
            y: -height + (parent.height + height) * Math.max(0, root.barrido)

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(root.prim, 0.14)
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1.5
                color: Qt.alpha(root.prim, 0.7)
            }
        }

        // Aviso al arrastrar cerca del borde de arriba
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colours.palette.m3tertiary, 0.16)
            opacity: root.cercaArriba ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 6

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "upload"
                    color: Colours.palette.m3tertiary
                    fontStyle: Tokens.font.icon.size(34).build()
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Suelta para enviarlo al móvil"
                    color: Colours.palette.m3tertiary
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // Borde (fuera del recorte, para que quede nítido)
    Rectangle {
        anchors.fill: cuerpo
        radius: cuerpo.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(root.prim, Math.min(1, 0.5 + 0.45 * root.realce + 0.3 * root.destello))
    }

    // Marcas de esquina: un guiño HUD discreto en dos esquinas opuestas
    Repeater {
        model: [
            {
                ax: 0,
                ay: 0
            },
            {
                ax: 1,
                ay: 1
            }
        ]

        // «Fijan» el panel al llegar: entran desde fuera hacia la esquina, como un visor
        // que engancha el objetivo; al irse se sueltan hacia fuera.
        Item {
            id: marca

            required property var modelData
            property real fija: root.llegado ? 1 : 0
            readonly property real fuera: (1 - fija) * 10

            x: modelData.ax ? root.width - width + 6 + fuera : -6 - fuera
            y: modelData.ay ? root.height - height + 6 + fuera : -6 - fuera
            width: 18
            height: 18
            opacity: 0.9 * fija
            visible: fija > 0

            Behavior on fija {
                NumberAnimation {
                    duration: HoloGeo.tMedio
                    easing.type: HoloGeo.curvaEntra
                }
            }

            Rectangle {
                y: parent.modelData.ay ? parent.height - 1.5 : 0
                width: parent.width
                height: 1.5
                color: root.prim
            }
            Rectangle {
                x: parent.modelData.ax ? parent.width - 1.5 : 0
                width: 1.5
                height: parent.height
                color: root.prim
            }
        }
    }

    HoverHandler {
        id: hover

        // Señala su fila (y su hilo) en la lista mientras el ratón está encima
        onHoveredChanged: {
            if (!root.item)
                return;
            if (hovered)
                HoloState.resaltado = root.item.n;
            else if (HoloState.resaltado === root.item.n)
                HoloState.resaltado = -1;
        }
    }

    // Clic en un visor = pasa a ser «esa»; clic derecho en cualquier panel = cerrarlo
    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: root.esVisor && root.llegado
        onTapped: {
            root.capa.alFrente(root.pid);
            if (root.item && !root.seleccionado)
                HoloState.seleccionar(root.item.n);
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.cerrarPanel()
    }
}
