# Warp — texto y archivos entre el PC y el móvil

Lo que se envía cae por un **agujero negro** y lo que llega sale por un **agujero blanco**, en el mismo sitio (borde
superior, centrado), como en Outer Wilds. Todo pasa por Olimpo (Pi, por el tailnet): sin puertos abiertos en el PC.
Diseño: `docs/superpowers/specs/2026-11-09-warp-design.md`.

## Del PC al móvil

| Cómo | Qué hace |
|---|---|
| **`Super+Shift+K`** | `warp rapido`: lo copiado (texto o imagen); si el portapapeles está vacío, lo subrayado. |
| Arrastrar un archivo al borde de arriba | El portal negro (drag-watch) → `olimpo enviar --progreso` (con barra, cancelar y aviso previo de tamaño). |
| Arrastrar **texto** seleccionado al borde de arriba | `warp texto -` (solo desde ventanas que vigila drag-watch: navegadores y gestores de archivos). |
| «Laura, manda X por warp» | Tool `assistant/laura/tools/warp.py`: texto dictado, portapapeles, selección, captura, último archivo de una carpeta, buscar + enviar (pregunta si hay dudas). |
| Terminal | `warp texto "…"`, `warp archivo <ruta>`, `warp buscar "pdf práctica redes"`, `warp ultimo Descargas`, `warp captura`. |

En el móvil llega a Olimpo como «Llegó del PC». Un texto sale con su contenido y un botón **Copiar** (una web no puede
escribir en el portapapeles sin un toque; la app nativa está en el roadmap de Olimpo).

Cada envío de `warp` escribe en `$XDG_RUNTIME_DIR/warp/salidas.jsonl`
(`{"fase":"enviando|ok|error","tipo","nombre","fragmento","origen","mensaje","tamano","ts"}`) y `Portals.qml` lo sigue con
`tail -F`: el agujero negro se abre, se traga una tarjeta y dice el resultado. **Los textos nunca se muestran ni se
notifican** (pueden ser claves): solo «Texto · N caracteres».

## Del móvil al PC

| Cómo | Qué hace |
|---|---|
| Android «Compartir → Olimpo» | Archivos → `~/Descargas/Desde el móvil/`; texto o enlace → **portapapeles del PC**. |
| Olimpo › Inicio › «Enviar texto al PC» | Caja + **Pegar** + **Enviar** → portapapeles del PC. |
| «Instinct, manda X por warp» | `POST /v1/paraelpc/texto` o `/v1/paraelpc` (ver `olimpo/docs/instinct.md` §6g). |
| «Instinct, mándame al móvil el pdf de…» | `POST /v1/warp/orden` → el puente ejecuta `warp buscar|ultimo|archivo --remoto` en el PC. |

El puente (`olimpo-puente.service`) copia el texto con `wl-copy` y añade una línea a
`$XDG_RUNTIME_DIR/olimpo-puente/llegadas.jsonl` (`{"tipo":"texto","texto","caracteres","copiado","ts"}`; los archivos
siguen siendo `{"ruta","nombre","tamano","mime","ts"}`). `modules/whitehole/WhiteHole.qml` abre el agujero blanco
(`shaders/whitehole.frag`) y suelta una tarjeta: «Copiado al portapapeles» (clic = copiar otra vez) o el archivo (clic
abrir, derecho carpeta, arrastrar). Si hay un arrastre en curso, las llegadas esperan a que acabe. El fichero vive en
tmpfs y el puente lo vacía al arrancar y al pasar de 256 KiB.

## Órdenes remotas (seguridad)

Desde el móvil solo se puede `buscar`, `ultimo` y `archivo`, y `warp --remoto` rechaza todo lo que esté fuera de `$HOME`,
en carpetas ocultas o con pinta de secreto (`.ssh`, `.gnupg`, `.config`, `.local`, `*.key`, `*.pem`, `*.token`, `.env*`,
`id_*`, `*.kdbx`…). Portapapeles, selección y captura solo se piden desde el PC. Hace falta el permiso `warp:pedir` en
el token (en la Pi: `python -m horas.tokens permisos <id> --añadir warp:pedir`).

## Pruebas

- `python3 -m unittest widgets/tests/test_warp.py` · `cd assistant && python3 -m pytest tests/test_warp.py`
- Olimpo: `.venv/bin/python -m pytest tests/tele tests/cli` · `cd app && npx vitest run`
- Sin móvil: `qs -c caelestia ipc call whitehole demoTexto "hola"` · `… whitehole demo <ruta>` ·
  `warp texto hola` (envía de verdad).
