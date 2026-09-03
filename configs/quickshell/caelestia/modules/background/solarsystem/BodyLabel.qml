pragma ComponentBehavior: Bound

// BodyLabel.qml — etiqueta de texto junto a un cuerpo del sistema solar v3.
//
// Estética de instrumento astronómico (Stellarium / carta estelar): mayúsculas
// pequeñas con MUCHO espaciado entre letras y opacidad baja. Vive de fondo todo
// el día: tiene que ser legible sobre negro pero no competir con las ventanas.
//
// Coste cero en reposo: NADA de animaciones en bucle. La única animación es un
// fundido de aparición de un disparo (Component.onCompleted). Todo lo demás es
// binding puro — se recoloca solo cuando cambian `targetX/Y`, el tamaño del
// campo o el texto, y no repinta si no cambia nada.
//
// CERO hex fijos en la lógica: los colores entran por `col` (y familias de
// fuente por `fontFamily`); los valores por defecto son solo un fallback para
// poder abrir el componente aislado.
//
// Debe instanciarse llenando a su padre (anchors.fill), que es el espacio de
// coordenadas de los cuerpos. Se hace aquí abajo por defecto.
//
// Integración: ver `_labelPreview.qml` en esta carpeta y la nota del informe
// sobre qué cablear en `SolarSystem.qml`.

import QtQuick

Item {
    id: root

    anchors.fill: parent
    clip: false

    // ---- Punto del cuerpo al que apunta (px del padre) ----
    property real targetX: 0
    property real targetY: 0
    property real targetRadius: 0
    // Y-coordinate used for the text block placement (to prevent collisions).
    // The guide line starts at targetY and ends at labelY.
    property real labelY: targetY

    // ---- Contenido ----
    property string title: ""
    property string subtitle: ""            // dato vivo opcional; vacío = no se dibuja

    // ---- Estilo ----
    // `col`: color del texto (viene de la paleta). Default = solo fallback.
    property color col: "#f8e1d6"
    // `emphasis` 0..1: importancia del cuerpo. Soles / agujero → etiqueta más
    // marcada (más grande, más opaca, más tracking) que un satélite pequeño.
    property real emphasis: 0.5
    // `variant`: "A" mínima · "B" con guía · "C" ficha de catálogo.
    property string variant: "A"
    // `showReticle`: el círculo de puntos de la variante C. Se apaga desde la
    // integración en los cuerpos que ya llevan un anillo pintado encima (agente
    // en curso, alerta de batería < 20 %) para que no se apilen dos círculos.
    // El nombre, la regla y el dato se conservan.
    property bool showReticle: true

    // ---- Fuente ----
    // Familia por defecto: la mono con la que ya viene configurado el shell
    // (caelestia usa "JetBrainsMono NF"). En la integración se puede cablear a
    // `Tokens.font.mono.small.family`. El aire de instrumento lo da el tracking
    // y la opacidad, no la familia concreta.
    property string fontFamily: "JetBrainsMono NF"
    property real basePixelSize: 12

    // ---- Límites del campo, para elegir el lado y no salirse de pantalla ----
    property real fieldWidth: parent ? parent.width : 1920
    property real fieldHeight: parent ? parent.height : 1080

    // ================= Derivados (binding puro) =================
    readonly property real _emph: Math.max(0, Math.min(1, emphasis))
    readonly property real _restOpacity: 0.28 + 0.36 * _emph
    readonly property real _titlePx: basePixelSize * (0.88 + 0.55 * _emph)
    readonly property real _subPx: _titlePx * 0.80
    readonly property real _tracking: 1.8 + 2.2 * _emph
    readonly property bool _hasSub: subtitle.length > 0 && variant !== "A"
    readonly property bool _side: variant === "B" || variant === "C"

    // separación mínima para no tapar el cuerpo. Las variantes con guía / ficha
    // piden algo más de aire para que la línea y la marca respiren.
    readonly property real _gap: targetRadius + 9 + 9 * _emph + (_side ? 14 : 0)
    readonly property real _margin: 8

    // ¿el texto se sale por la derecha? → colócalo a la izquierda del cuerpo
    readonly property bool _placeLeft:
        targetX + _gap + content.implicitWidth + _margin > fieldWidth
    // en layout "arriba-derecha" (variante A), ¿se sale por arriba? → abajo
    readonly property bool _placeBelow:
        !_side && (targetY - _gap - content.implicitHeight < _margin)

    readonly property real _contentX: _placeLeft
        ? targetX - _gap - content.implicitWidth
        : targetX + _gap
    readonly property real _contentY: _side
        ? Math.max(_margin,
            Math.min(fieldHeight - content.implicitHeight - _margin,
                     labelY - content.implicitHeight / 2))
        : (_placeBelow ? labelY + _gap
                       : labelY - _gap - content.implicitHeight)

    // ================= Marca de observatorio (variante C) =================
    // Círculo de puntos alrededor del cuerpo. Estático: un Repeater, sin animar.
    Repeater {
        model: (root.variant === "C" && root.showReticle) ? 16 : 0
        delegate: Rectangle {
            id: dot
            required property int index
            readonly property real _ang: dot.index / 16 * 2 * Math.PI
            readonly property real _rr: root.targetRadius + 5 + 3 * root._emph
            width: 1.6
            height: 1.6
            radius: 0.8
            antialiasing: true
            color: root.col
            opacity: root._restOpacity * 0.55
            x: root.targetX + Math.cos(dot._ang) * dot._rr - width / 2
            y: root.targetY + Math.sin(dot._ang) * dot._rr - height / 2
        }
    }

    // ================= Línea guía (variantes B y C) =================
    // Recta finísima del borde del cuerpo al inicio del texto. Rectangle de 1 px
    // rotado — sin Canvas, sin repintado.
    Rectangle {
        id: guide
        visible: root._side
        antialiasing: true
        height: 1
        color: root.col
        opacity: root._restOpacity * 0.30

        readonly property real _ax: root._placeLeft
            ? root.targetX - root.targetRadius - 3
            : root.targetX + root.targetRadius + 3
        readonly property real _ay: root.targetY
        readonly property real _bx: root._placeLeft
            ? root._contentX + content.implicitWidth + 5
            : root._contentX - 5
        readonly property real _by: content.y + content.implicitHeight / 2

        x: _ax
        y: _ay
        width: Math.max(0, Math.hypot(_bx - _ax, _by - _ay))
        transformOrigin: Item.TopLeft
        rotation: Math.atan2(_by - _ay, _bx - _ax) * 180 / Math.PI
    }

    // ================= Bloque de texto =================
    Column {
        id: content
        x: root._contentX
        y: root._contentY
        spacing: 3

        Text {
            id: titleText
            text: root.title.toUpperCase()
            color: root.col
            opacity: root._restOpacity
            renderType: Text.NativeRendering
            font.family: root.fontFamily
            font.pixelSize: root._titlePx
            font.letterSpacing: root._tracking
            font.weight: root._emph > 0.6 ? Font.Medium : Font.Normal
        }

        // regla horizontal finísima bajo el nombre (variante C)
        Rectangle {
            visible: root.variant === "C"
            width: Math.max(26, titleText.implicitWidth * 0.82)
            height: 1
            antialiasing: true
            color: root.col
            opacity: root._restOpacity * 0.45
        }

        Text {
            visible: root._hasSub
            text: root.subtitle
            color: root.col
            opacity: root._restOpacity * 0.68
            renderType: Text.NativeRendering
            font.family: root.fontFamily
            font.pixelSize: root._subPx
            font.letterSpacing: root._tracking * 0.55
        }
    }

    // ================= Aparición: fundido de un disparo =================
    // NO es un bucle. Corre una vez al crearse y no vuelve a tocarse.
    opacity: 0
    Component.onCompleted: appear.start()
    NumberAnimation {
        id: appear
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: 360
        easing.type: Easing.OutCubic
    }
}
