pragma ComponentBehavior: Bound

// _healthPreview.qml — banco de pruebas de HealthPlanet.qml (archivo de desarrollo,
// el guion bajo lo marca). No entra en el shell.
//
//   qs -p configs/quickshell/caelestia/modules/background/solarsystem/_healthPreview.qml
//
// Cuatro estados lado a lado con datos fijos: real (2026-10-26, hoy parcial), semana buena
// con la meta cumplida (inventada), sin conexión con caché vieja y sin credenciales.
// Paleta = la del tema del 2026-10-26.

import QtQuick
import Quickshell

FloatingWindow {
    id: win
    implicitWidth: 1920
    implicitHeight: 420
    color: "#0b0705"

    function d(date, steps, sleepH, deepMin, workouts, habits) {
        return { date: date, steps: steps, sleepH: sleepH, deepMin: deepMin, restingHr: null,
                 workouts: workouts || 0, habits: habits || [] };
    }
    readonly property var goal: ({ steps: 10000, sleepH: 7.5, sessionsPerWeek: 4 })
    readonly property var realDays: [
        d("2026-10-20", 8161, 2.58, 24), d("2026-10-21", 4613, 5.95, 6), d("2026-10-22", 11213, 1.43, 19),
        d("2026-10-23", 660, 9.13, 65, 0, ["creatina"]), d("2026-10-24", 1700, 7.75, 62),
        d("2026-10-25", 6919, 0.55, null), d("2026-10-26", 330, 4.97, null)
    ]
    readonly property var goodDays: [
        d("2026-10-20", 12040, 7.6, 60, 1, ["creatina"]), d("2026-10-21", 10480, 6.9, 55, 0, ["creatina"]),
        d("2026-10-22", null, null, null), d("2026-10-23", 10900, 7.9, 70, 1, ["creatina"]),
        d("2026-10-24", 13020, 7.1, 58, 1), d("2026-10-25", 9100, 8.2, 66), d("2026-10-26", 10650, 6.2, 52, 1, ["creatina"])
    ]
    readonly property var cases: [
        { title: "OK · DATOS REALES (HOY PARCIAL)",
          h: { status: "ok", today: "2026-10-26", goal: goal, days: realDays, weekWorkouts: 0,
               fetchedAt: new Date().toISOString() } },
        { title: "OK · META CUMPLIDA (INVENTADA)",
          h: { status: "ok", today: "2026-10-26", goal: goal, days: goodDays, weekWorkouts: 1,
               fetchedAt: new Date().toISOString() } },
        { title: "SIN CONEXIÓN · CACHÉ DE AYER",
          h: { status: "offline", today: "2026-10-27", goal: goal, weekWorkouts: 0,
               days: realDays.slice(1).concat([d("2026-10-27", null, null, null)]),
               fetchedAt: new Date(Date.now() - 9 * 3600000).toISOString() } },
        { title: "SIN CREDENCIALES",
          h: { status: "nocreds", today: "2026-10-26", days: [] } }
    ]

    Row {
        anchors.fill: parent
        Repeater {
            model: win.cases
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                width: win.width / 4
                height: win.height
                Text {
                    x: 16; y: 12
                    text: cell.modelData.title
                    color: "#f9b7a3"; opacity: 0.8
                    font.family: "JetBrainsMono NF"; font.pixelSize: 12; font.letterSpacing: 2
                }
                HealthPlanet {
                    anchors.fill: parent
                    geo: ({ x: 120, y: 190, r: 23.76, moonR: 41.58, moonPhase: 0.7 + cell.index })
                    health: cell.modelData.h
                    sc: 1
                    zoom: 1
                    colPrimary: "#f9b7a3"
                    colPrimaryC: "#764636"
                    colInk: "#f9e0d9"
                    colOutline: "#84716c"
                    colVoid: Qt.darker("#130d0a", 3)
                }
            }
        }
    }
}
