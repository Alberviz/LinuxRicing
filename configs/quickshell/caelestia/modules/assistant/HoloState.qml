pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.assistant

// Modelo de estado y puente de control para paneles holográficos de Laura.
// Mantiene los elementos listados y paneles visibles recibidos desde el daemon.
Singleton {
    id: root

    property var items: []
    property var paneles: []
    property int seleccionado: -1
    readonly property bool activo: paneles.length > 0

    signal opened(string pid)
    signal closed(var ids)
    signal sent(string pid)
    signal cleared()

    function handle(ev): void {
        if (!ev || ev.type !== "holo")
            return;

        if (ev.items !== undefined && Array.isArray(ev.items))
            root.items = ev.items;
        if (ev.paneles !== undefined && Array.isArray(ev.paneles))
            root.paneles = ev.paneles;
        if (ev.seleccionado !== undefined)
            root.seleccionado = (ev.seleccionado === null || ev.seleccionado === undefined) ? -1 : ev.seleccionado;

        switch (ev.op) {
        case "open":
            if (ev.panel && ev.panel.id)
                root.opened(ev.panel.id);
            break;
        case "close":
            if (ev.ids && Array.isArray(ev.ids))
                root.closed(ev.ids);
            break;
        case "sent":
            if (ev.ids && ev.ids.length > 0)
                root.sent(ev.ids[0]);
            else if (ev.panel && ev.panel.id)
                root.sent(ev.panel.id);
            break;
        case "clear":
            root.cleared();
            break;
        case "snapshot":
        case "list":
        case "select":
        case "page":
        default:
            break;
        }
    }

    function item(n: int): var {
        if (!root.items)
            return null;
        for (let i = 0; i < root.items.length; i++) {
            if (root.items[i].n === n)
                return root.items[i];
        }
        return null;
    }

    // Funciones de acción de ratón hacia el daemon
    function abrir(n: int): void {
        Laura.ctrl("holo-open " + n);
    }

    function seleccionar(n: int): void {
        Laura.ctrl("holo-select " + n);
    }

    function cerrar(pid: string): void {
        Laura.ctrl("holo-close " + pid);
    }

    function cerrarTodo(): void {
        Laura.ctrl("holo-close all");
    }

    function enviar(n: int): void {
        Laura.ctrl("holo-send " + n);
    }

    function pagina(pid: string, p: int): void {
        Laura.ctrl("holo-page " + pid + " " + p);
    }

    function externo(n: int): void {
        Laura.ctrl("holo-ext " + n);
    }

    // Modo demo local sin necesidad de daemon
    Timer {
        id: demoTimer
        interval: 1200
        repeat: false
        onTriggered: root._lanzarVisoresDemo()
    }

    function demo(): void {
        demoTimer.stop();
        const demoImg = "/usr/share/pixmaps/archlinux-logo.png";
        const now = Date.now() / 1000;
        const listaItems = [
            { n: 1, ruta: demoImg, nombre: "archlinux-logo.png", tipo: "imagen", tamano: 3813, mtime: now - 120, enviado: false },
            { n: 2, ruta: "/home/alberviz/Descargas/practica3_redes.pdf", nombre: "practica3_redes.pdf", tipo: "pdf", tamano: 1840000, mtime: now - 3600, enviado: false },
            { n: 3, ruta: "/home/alberviz/Descargas/notas_reunion.md", nombre: "notas_reunion.md", tipo: "texto", tamano: 12400, mtime: now - 7200, enviado: false },
            { n: 4, ruta: "/home/alberviz/Descargas/demo_presentacion.mp4", nombre: "demo_presentacion.mp4", tipo: "video", tamano: 45000000, mtime: now - 86400, enviado: false },
            { n: 5, ruta: "/home/alberviz/Descargas/audio_clase.opus", nombre: "audio_clase.opus", tipo: "audio", tamano: 8500000, mtime: now - 90000, enviado: false },
            { n: 6, ruta: "/home/alberviz/Descargas/dataset_v1.csv", nombre: "dataset_v1.csv", tipo: "texto", tamano: 95000, mtime: now - 120000, enviado: false },
            { n: 7, ruta: "/home/alberviz/Descargas/backup_config.tar.gz", nombre: "backup_config.tar.gz", tipo: "otro", tamano: 3200000, mtime: now - 200000, enviado: false },
            { n: 8, ruta: "/home/alberviz/Descargas/WhatsApp 21.04.jpg", nombre: "WhatsApp 21.04.jpg", tipo: "imagen", tamano: 412000, mtime: now - 250000, enviado: false }
        ];

        const panelLista = {
            id: "lista",
            kind: "lista",
            titulo: "Descargas",
            item_n: null,
            payload: { items: listaItems }
        };

        root.handle({
            type: "holo",
            op: "list",
            items: listaItems,
            paneles: [panelLista],
            seleccionado: null,
            panel: panelLista,
            ids: null
        });

        demoTimer.restart();
    }

    function _lanzarVisoresDemo(): void {
        const demoImg = "/usr/share/pixmaps/archlinux-logo.png";
        const v1 = {
            id: "v1",
            kind: "visor",
            titulo: "archlinux-logo.png",
            item_n: 1,
            payload: { tipo: "imagen", src: demoImg, w: 480, h: 480 }
        };

        const v2 = {
            id: "v2",
            kind: "visor",
            titulo: "practica3_redes.pdf",
            item_n: 2,
            payload: {
                tipo: "pdf",
                src: demoImg,
                pagina: 1,
                paginas: 12
            }
        };

        const v3 = {
            id: "v3",
            kind: "visor",
            titulo: "notas_reunion.md",
            item_n: 3,
            payload: {
                tipo: "texto",
                texto: "# Notas de reunión\n\n- Revisión de arquitectura de red\n- Pruebas de latencia completadas\n- Tareas pendientes para el sprint:\n  * Configurar cortafuegos\n  * Desplegar nuevo nodo de almacenamiento",
                formato: "markdown",
                truncado: false
            }
        };

        const v7 = {
            id: "v7",
            kind: "visor",
            titulo: "backup_config.tar.gz",
            item_n: 7,
            payload: {
                tipo: "otro",
                mime: "application/gzip",
                icono: "folder_zip"
            }
        };

        const p1 = root.paneles.slice();
        p1.push(v1);
        root.handle({
            type: "holo",
            op: "open",
            items: root.items,
            paneles: p1,
            seleccionado: 1,
            panel: v1,
            ids: null
        });

        const p2 = p1.slice();
        p2.push(v2);
        root.handle({
            type: "holo",
            op: "open",
            items: root.items,
            paneles: p2,
            seleccionado: 2,
            panel: v2,
            ids: null
        });

        const p3 = p2.slice();
        p3.push(v3);
        root.handle({
            type: "holo",
            op: "open",
            items: root.items,
            paneles: p3,
            seleccionado: 3,
            panel: v3,
            ids: null
        });

        const p4 = p3.slice();
        p4.push(v7);
        root.handle({
            type: "holo",
            op: "open",
            items: root.items,
            paneles: p4,
            seleccionado: 7,
            panel: v7,
            ids: null
        });
    }

    IpcHandler {
        target: "holo"

        function demo(): void {
            root.demo();
        }

        function clear(): void {
            demoTimer.stop();
            root.cerrarTodo();
            root.handle({
                type: "holo",
                op: "clear",
                items: [],
                paneles: [],
                seleccionado: null,
                panel: null,
                ids: null
            });
        }
    }
}
