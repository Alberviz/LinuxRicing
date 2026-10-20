pragma ComponentBehavior: Bound

import QtQuick

// Un brazo de la luz de borde: una cola que se desvanece y recorre el
// perímetro de la pantalla (puntos de la «convergencia a» del mockup).
// Son Rectangles con gradiente lineal, uno por tramo recto del perímetro.
Item {
    id: trail

    // Geometría de pantalla
    required property real sw
    required property real sh
    required property real ty
    readonly property real m: 3

    // -1: recorre el perímetro hacia atrás desde el centro del borde inferior; +1: hacia delante
    required property int dir
    required property real head // posición s de la cabeza
    required property real tail // longitud de la cola
    required property color tint
    property real thin: 3
    property real wide: 9

    readonly property var lens: [sh - m - ty, sw - 2 * m, sh - 2 * m, sw - 2 * m, ty - m]
    readonly property var starts: {
        let a = [0], s = 0;
        for (let i = 0; i < 4; i++) {
            s += lens[i];
            a.push(s);
        }
        return a;
    }

    function alphaAt(s: real): real {
        if (tail <= 0.5)
            return 0;
        const k = dir < 0 ? (s - head) / tail : (head - s) / tail;
        return Math.max(0, Math.min(1, 1 - k));
    }

    // Tramo i -> {x,y,w,h,vertical,a0,a1} para un grosor de línea t
    function seg(i: int, t: real): var {
        const lo = dir < 0 ? head : head - tail;
        const hi = dir < 0 ? head + tail : head;
        const S = starts[i], L = lens[i];
        const a = Math.max(lo, S), b = Math.min(hi, S + L);
        if (!(b > a) || tail <= 0.5)
            return {
                on: false
            };
        const da = a - S, db = b - S;
        const Aa = alphaAt(a), Ab = alphaAt(b);
        switch (i) {
        case 0:
            return {
                on: true,
                vert: true,
                x: sw - m - t / 2,
                y: ty + da,
                w: t,
                h: db - da,
                a0: Aa,
                a1: Ab
            };
        case 1:
            return {
                on: true,
                vert: false,
                x: sw - m - db,
                y: sh - m - t / 2,
                w: db - da,
                h: t,
                a0: Ab,
                a1: Aa
            };
        case 2:
            return {
                on: true,
                vert: true,
                x: m - t / 2,
                y: sh - m - db,
                w: t,
                h: db - da,
                a0: Ab,
                a1: Aa
            };
        case 3:
            return {
                on: true,
                vert: false,
                x: m + da,
                y: m - t / 2,
                w: db - da,
                h: t,
                a0: Aa,
                a1: Ab
            };
        }
        return {
            on: true,
            vert: true,
            x: sw - m - t / 2,
            y: m + da,
            w: t,
            h: db - da,
            a0: Aa,
            a1: Ab
        };
    }

    Repeater {
        model: 10

        Rectangle {
            id: r

            required property int index
            readonly property bool isWide: index >= 5
            readonly property var g: trail.seg(index % 5, isWide ? trail.wide : trail.thin)
            readonly property real k: isWide ? 0.13 : 0.9

            visible: g.on
            x: g.x ?? 0
            y: g.y ?? 0
            width: g.w ?? 0
            height: g.h ?? 0
            radius: isWide ? 0 : 1
            gradient: Gradient {
                orientation: r.g.vert ? Gradient.Vertical : Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: Qt.alpha(trail.tint, (r.g.a0 ?? 0) * r.k)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(trail.tint, (r.g.a1 ?? 0) * r.k)
                }
            }
        }
    }
}
