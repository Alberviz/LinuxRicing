pragma ComponentBehavior: Bound

// HealthPlanet.qml — planeta «Cuerpo»: la salud del reloj (Amazfit GTS 2).
//
// Spec: docs/sistema-solar-salud-DISENO.md §4. Un planeta fijo con su propio séquito:
//  · arco de órbita = pasos de hoy / meta (sonda en la punta; meta cumplida → arco
//    cerrado + halo);
//  · terminador día/noche = sueño de anoche / meta de sueño;
//  · lunas = entrenos de la semana ISO (llenas) sobre la meta semanal (huecas);
//  · 7 cuentas = pasos de los últimos 7 días (la racha), marca encima = hábito.
// Sin datos → planeta fantasma; datos atrasados → arco gris con el último día bueno.
//
// Todo Shape/Rectangle (GPU). Sin temporizadores ni animaciones propias: se repinta
// cuando cambia `health` (cada 20 min) o `geo` (el ticker de Sim.js, para las lunas).

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    // --- Entradas ---
    property var geo: null                     // layout.health {x, y, r, moonR, moonPhase}
    property var health: ({ status: "loading", days: [] })
    property real sc: 1                        // layout.scale (h / 1080)
    property real zoom: 0                      // hover 0..1 (detalle de la etiqueta)
    property string labelFont: "JetBrainsMono NF"
    property color colPrimary: "#f7b999"
    property color colPrimaryC: "#764636"
    property color colInk: "#f8e1d6"
    property color colOutline: "#84716c"
    property color colVoid: "#050302"

    visible: geo !== null

    // --- Datos derivados (cambian con `health`, no por frame) ---
    readonly property string status: health && health.status ? health.status : "loading"
    readonly property var days: health && health.days ? health.days : []
    readonly property var goal: health && health.goal ? health.goal : ({ steps: 10000, sleepH: 7.5, sessionsPerWeek: 4 })
    readonly property bool ghost: !(status === "ok" || status === "offline") || days.length === 0
    readonly property var todayDay: {
        for (let i = days.length - 1; i >= 0; i--)
            if (days[i].date === health.today) return days[i];
        return null;
    }
    // Hoy si ya hay pasos; si no (medianoche, retraso de Zepp), el último día con pasos.
    readonly property var stepsDay: {
        if (todayDay && typeof todayDay.steps === "number") return todayDay;
        for (let i = days.length - 1; i >= 0; i--)
            if (typeof days[i].steps === "number") return days[i];
        return null;
    }
    // Por fecha, no por identidad: cada acceso a una lista de un `var` crea un objeto nuevo.
    readonly property bool stale: status === "offline"
        || (stepsDay !== null && (todayDay === null || stepsDay.date !== todayDay.date))
    readonly property real frac: (!ghost && stepsDay) ? _clamp01(stepsDay.steps / goal.steps) : 0
    readonly property bool goalMet: !ghost && !stale && frac >= 1
    readonly property var sleepH: (!ghost && todayDay && typeof todayDay.sleepH === "number") ? todayDay.sleepH : null
    readonly property real lit: sleepH === null ? 1 : _clamp01(sleepH / goal.sleepH)
    readonly property bool sleepPartial: sleepH !== null && (sleepH < 3 || !todayDay.deepMin)
    readonly property int moonsN: Math.max(1, Math.min(7, goal.sessionsPerWeek || 4))
    readonly property int moonsDone: ghost ? 0 : Math.min(moonsN, health.weekWorkouts || 0)

    // --- Geometría ---
    readonly property real cx: geo ? geo.x : 0
    readonly property real cy: geo ? geo.y : 0
    readonly property real r: geo ? geo.r : 0
    readonly property real orx: r * 3.0                  // órbita del arco de pasos
    readonly property real ory: orx * 0.42               // misma perspectiva que las órbitas
    readonly property real beadY: cy + r * 2.9
    readonly property real _theta: (-90 + 360 * frac) * Math.PI / 180

    function _clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
    function _a(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function _lit(c, k) { return Qt.rgba(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, 1); }
    function _dk(c, k) { return Qt.rgba(c.r * (1 - k), c.g * (1 - k), c.b * (1 - k), 1); }

    // --- Textos de la etiqueta (solo dato real) ---
    readonly property var _es: Qt.locale("es_ES")
    function _n(v) { return Number(v).toLocaleString(_es, "f", 0); }
    function _dayName(iso) {
        const y = new Date(Date.parse(health.today + "T12:00:00") - 86400000);
        if (iso === Qt.formatDate(y, "yyyy-MM-dd")) return "ayer";
        return ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"][new Date(iso + "T12:00:00").getDay()];
    }
    function _age() {
        const t = Date.parse(health.fetchedAt || "");
        if (isNaN(t)) return "";
        const h = Math.round((Date.now() - t) / 3600000);
        return h < 1 ? "act. " + Qt.formatTime(new Date(t), "HH:mm") : "hace " + h + " h";
    }
    readonly property string _line1: {
        if (ghost) return status === "auth" ? "credenciales rechazadas" : (status === "loading" ? "" : "sin datos");
        if (!stepsDay) return "sin pasos";
        const s = stale ? _dayName(stepsDay.date) + " " + _n(stepsDay.steps) + " pasos"
                        : _n(stepsDay.steps) + " / " + _n(goal.steps) + " pasos";
        return status === "offline" ? s + "\nsin conexión" : s;
    }
    // Detalle en líneas cortas: así la etiqueta cabe a la derecha del planeta (x ≈ 0,81·w)
    // y no salta a la izquierda, hacia la órbita del cometa.
    readonly property string _detail: {
        if (ghost) return "";
        const lines = [];
        lines.push(sleepH === null ? "sueño —"
                   : "sueño " + Number(sleepH).toLocaleString(_es, "f", 1) + " h" + (sleepPartial ? " (parcial)" : ""));
        let l2 = moonsDone + "/" + moonsN + " entrenos";
        if (todayDay && typeof todayDay.restingHr === "number") l2 += " · FC " + todayDay.restingHr;
        lines.push(l2);
        const age = _age();
        if (age) lines.push(age);
        return lines.join("\n");
    }

    // ===== Halo de meta cumplida (por detrás de todo) =====
    Shape {
        anchors.fill: parent
        visible: root.goalMet
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.cx; centerY: root.cy; centerRadius: root.r * 2.6
                focalX: root.cx; focalY: root.cy
                GradientStop { position: 0.38; color: root._a(root.colPrimary, 0.30) }
                GradientStop { position: 1.0; color: root._a(root.colPrimary, 0) }
            }
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.r * 2.6; radiusY: root.r * 2.6
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    // ===== Órbita base + arco de pasos =====
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root._a(root.colPrimary, root.ghost ? 0.10 : 0.13)
            strokeWidth: 1 * root.sc
            strokeStyle: root.ghost ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: [3, 5]
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.orx; radiusY: root.ory
                startAngle: 0; sweepAngle: 360
            }
        }
        ShapePath {
            strokeColor: root.stale ? root._a(root.colOutline, 0.75) : root._a(root.colPrimary, 0.85)
            strokeWidth: root.frac > 0 ? 2.2 * root.sc : 0
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.orx; radiusY: root.ory
                startAngle: -90; sweepAngle: 360 * root.frac
            }
        }
    }
    // Sonda en la punta del arco (halo + núcleo, como la cabeza del cometa).
    Rectangle {
        visible: root.frac > 0
        width: 10 * root.sc; height: width; radius: width / 2
        x: root.cx + root.orx * Math.cos(root._theta) - width / 2
        y: root.cy + root.ory * Math.sin(root._theta) - height / 2
        color: root._a(root.stale ? root.colOutline : root.colPrimary, 0.35)
    }
    Rectangle {
        visible: root.frac > 0
        width: 3.4 * root.sc; height: width; radius: width / 2
        x: root.cx + root.orx * Math.cos(root._theta) - width / 2
        y: root.cy + root.ory * Math.sin(root._theta) - height / 2
        color: root.stale ? root.colOutline : root.colInk
    }

    // ===== Esfera + terminador (sueño) =====
    Shape {
        id: sphere
        anchors.fill: parent
        opacity: root.ghost ? 0.28 : 1
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: root.cx; centerY: root.cy; centerRadius: root.r
                focalX: root.cx - root.r * 0.35; focalY: root.cy - root.r * 0.40
                GradientStop { position: 0.0; color: root._lit(root.colPrimary, 0.55) }
                GradientStop { position: 0.45; color: root.colPrimary }
                GradientStop { position: 0.85; color: root.colPrimaryC }
                GradientStop { position: 1.0; color: root._dk(root.colPrimaryC, 0.5) }
            }
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.r; radiusY: root.r
                startAngle: 0; sweepAngle: 360
            }
        }
        // Lado noche: semicírculo derecho + arco elíptico del terminador. Con lit < 0.5 la
        // sombra pasa de la mitad (el terminador abomba a la izquierda); con lit > 0.5 es
        // una media luna a la derecha.
        ShapePath {
            strokeColor: "transparent"
            fillColor: (root.sleepH !== null && root.lit < 0.999) ? root._a(root.colVoid, 0.78) : "transparent"
            startX: root.cx; startY: root.cy - root.r
            PathArc {
                x: root.cx; y: root.cy + root.r
                radiusX: root.r; radiusY: root.r
                direction: PathArc.Clockwise
            }
            PathArc {
                x: root.cx; y: root.cy - root.r
                radiusX: Math.max(0.5, root.r * Math.abs(1 - 2 * root.lit)); radiusY: root.r
                direction: root.lit < 0.5 ? PathArc.Clockwise : PathArc.Counterclockwise
            }
        }
    }

    // ===== Lunas = entrenos de la semana (las del lado de atrás, detrás de la esfera) =====
    Repeater {
        model: root.moonsN
        delegate: Rectangle {
            required property int index
            readonly property real ang: (root.geo ? root.geo.moonPhase : 0) + index * 2 * Math.PI / root.moonsN
            readonly property bool done: index < root.moonsDone
            z: Math.sin(ang) < 0 ? -1 : 1
            width: 6.4 * root.sc; height: width; radius: width / 2
            x: root.cx + (root.geo ? root.geo.moonR : 0) * Math.cos(ang) - width / 2
            y: root.cy + (root.geo ? root.geo.moonR : 0) * 0.55 * Math.sin(ang) - height / 2
            color: done ? root._a(root.colInk, 0.9) : "transparent"
            border.width: done ? 0 : 1
            border.color: root._a(root.colOutline, root.ghost ? 0.25 : 0.40)
        }
    }

    // ===== Racha: 7 cuentas (la última = hoy) =====
    Repeater {
        model: 7
        delegate: Item {
            id: bead
            required property int index
            readonly property var d: (!root.ghost && root.days.length === 7) ? root.days[index] : null
            readonly property real f: (d && typeof d.steps === "number") ? root._clamp01(d.steps / root.goal.steps) : -1
            readonly property real bx: root.cx - 66 * root.sc + index * 22 * root.sc
            Rectangle {
                readonly property real sz: (bead.f >= 1 ? 8 : 6) * root.sc
                width: sz; height: sz; radius: sz / 2
                x: bead.bx - sz / 2; y: root.beadY - sz / 2
                color: bead.f < 0 ? "transparent"
                     : root._a(root.colPrimary, bead.f >= 1 ? 0.95 : 0.15 + 0.45 * bead.f)
                border.width: bead.f < 0 ? 1 : 0
                border.color: root._a(root.colOutline, 0.35)
            }
            // aro de hoy
            Rectangle {
                visible: bead.index === 6
                width: 14 * root.sc; height: width; radius: width / 2
                x: bead.bx - width / 2; y: root.beadY - height / 2
                color: "transparent"
                border.width: 1
                border.color: root._a(root.colInk, root.ghost ? 0.2 : 0.5)
            }
            // hábito hecho ese día
            Rectangle {
                visible: bead.d !== null && bead.d.habits && bead.d.habits.length > 0
                width: 1.8 * root.sc; height: width
                x: bead.bx - width / 2; y: root.beadY - 10 * root.sc
                color: root._a(root.colInk, 0.7)
            }
        }
    }

    // ===== Etiqueta =====
    BodyLabel {
        variant: "B"
        fontFamily: root.labelFont
        basePixelSize: 12
        showReticle: false
        targetX: root.cx
        targetY: root.cy
        targetRadius: root.orx
        title: "Cuerpo"
        subtitle: root._line1 + (root.zoom > 0.01 && root._detail ? "\n" + root._detail : "")
        detailAmount: 1
        emphasis: (root.ghost ? 0.10 : 0.22) + 0.45 * root.zoom
        col: root.colPrimary
    }

    // Clic en el planeta: abre la vista web del gym-hub (tiene su propio login).
    MouseArea {
        x: root.cx - root.orx; y: root.cy - root.r * 1.6
        width: root.orx * 2; height: root.r * 3.2
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.health && root.health.webUrl) Qt.openUrlExternally(root.health.webUrl)
    }
}
