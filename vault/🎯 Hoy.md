---
tags:
  - home
  - backlog
actualizado: 2026-09-01
---

# 🎯 Hoy · ¿Qué hago?

Lista viva y priorizada de todo lo que hay pendiente en el setup **LinuxRicing**: lo que
le vas pidiendo a los agentes y los proyectos del [[Roadmap Maestro de Innovaciones]].

> [!tip] Cómo funciona
> - **Las tareas se añaden solas.** Cuando le dices a un agente *«añade esta tarea»* o
>   *«esto para el futuro»*, él crea la nota en `Backlog/` y aparece aquí.
> - **Tú mandas en el orden:** edita `prioridad` (1 = ya … 5 = algún día) y `estado`
>   directamente en la tabla.
> - Cambia de vista con las pestañas de la tabla: **En curso · Hoy · Todo · Por área ·
>   Reciente · Hechas · Tablero**.

---

## 🪣 Bucket List — todo lo que queremos construir

Vista de pájaro de los **grandes objetivos** del setup, agrupados por sistema.
Es el «hacia dónde vamos»; la rodaja accionable con prioridades está en las
tablas de abajo y el diseño largo en [[Roadmap Maestro de Innovaciones]].
Leyenda: 🟢 hecho · 🟡 en curso · 🔵 pendiente.

### 🔊 Sistema de sonido del ecosistema
- 🟢 Sonidos de las notificaciones de agentes (inicio / completado / error, 4 paletas CC0, No Molestar). → [[Sonidos de notificaciones de agentes]]
- 🔵 **Sonido completo del ecosistema:** paleta sonora coherente para *todos* los eventos (conexión/desconexión de dispositivos, batería baja, carga al 100 %, OSD de volumen/brillo, escenas, captura de pantalla), emparejada con el flash RGB. → [[Sistema de sonido completo del ecosistema]]
- 🔵 **Panel «Sonidos»** en los ajustes: interruptor global, slider de volumen, selector de paleta con previsualización, casillas por categoría. → [[Panel de ajustes de Sonidos]]

### 🔔 Terminar el sistema de notificaciones de agentes
- 🟢 v1: `agent-notify`, toasts enriquecidos, halo de acento, tarjeta popout, auto-descarte.
- 🟢 *Running pulse* v2: aro palpitante + halo neón mientras el agente trabaja.
- 🟢 Auto-intercepción de las notificaciones nativas de Claude / Antigravity hacia el pipeline enriquecido.
- 🔵 **Estado de error:** halo ámbar + pip cuando un agente termina con fallo o cancelado. → [[Estado error — halo ámbar en el pip]]
- 🔵 **Agente fuera de vista:** indicador en el extremo de la tira de pips cuando el workspace del agente no está en el grupo paginado. → [[Indicador de agente en workspace fuera de vista]]
- 🔵 *Running pulse* estilo **arc / spinner** como alternativa al parpadeo. → [[Running pulse — estilo arc (spinner)]]

### 🌈 Terminar el sistema de LEDs
- 🟢 Sincronización de tema en teclado Akko, placa ASUS, RAM, tira MagicHome, base y ratón MCHOSE.
- 🟢 Motor de iluminación reactiva a la batería (`battery-lighting`) con efectos de una sola escritura.
- 🟡 **Telemetría real del teclado Akko:** por cable el firmware no da % (documentado, el widget ya no lo inventa — ver Tarea del 2026-09-01 en [[Base de Datos de Errores]]); falta una lectura 2.4 GHz fiable sin EMA. → [[Telemetría de batería real del teclado Akko]]
- 🔵 **Daemon modular `rgbd`:** unificar los scripts sueltos en un servicio asíncrono con eventos, snapshots y cero colisiones de bus. → [[Daemon modular de iluminación (rgbd)]]
- 🔵 Iluminación del **cuerpo del ratón K7 Ultra** (independiente de la base). → [[Iluminación del cuerpo del ratón MCHOSE K7 Ultra]]
- 🔵 Efectos ambiente: Ambilight, flashes por app, espejo de OSD, modo cine, circadiana, CAVA en la tira. → [[Ambilight — screen mirroring en la tira LED]] · [[Flashes de notificación inteligentes]] · [[Espejo de barra OSD (volumen y brillo)]]

### 🤖 Agentes de IA — nuevas capacidades
- 🔵 **Agente que controla el gestor de arranque dual-boot**, con tema visual propio: decide y aplica en qué SO arranca el PC (boot-next de una vez), menú de arranque con skin Material You. → [[Agente IA para el gestor de arranque dual-boot]]
- 🔵 Sync bidireccional con **Google Tasks** en el Deck de widgets. → [[Sync bidireccional con Google Tasks]]

### 🖥️ UI, widgets y escritorio
- 🔵 **Centro de Iluminación RGB:** ventana overlay única para toda la iluminación. → [[Centro de Iluminación RGB]]
- 🔵 **Suite de Control y Laboratorio de Hardware:** pestañas de RGB + gestor de widgets + asistente guiado para añadir hardware USB nuevo. → [[Suite de Control y Laboratorio de Hardware (Vision)]]
- 🔵 **Escenas de 1 clic** (Gaming / Trabajo / Cine / Descanso / Apagado total) y perfiles de escena por hora y contexto. → [[Escenas de 1 clic]] · [[Perfiles de escena por hora y contexto]]
- 🔵 Rediseño de widgets y animaciones de carga. → [[Rediseño de Widgets y Animaciones de Carga]]
- 🔵 **Paridad Windows-Linux:** replicar el escritorio en Windows 11 (Desktop Deck QML, YASB, Komorebi, daemon de fondo). → [[Plan Maestro de Paridad Windows-Linux]]

### 🎵 Música e inmersión
- 🔵 Overlay de **letras sincronizadas** sobre el visualizador orbital. → [[Overlay de letras sincronizadas (Synced Lyrics)]]
- 🔵 Paleta reactiva por **carátula del álbum** (en vez del wallpaper). → [[Paleta reactiva por carátula del álbum]]
- 🔵 Pulsación rítmica **CAVA** en la tira LED. → [[Pulsación rítmica CAVA en la tira LED]]

### 🎮 Gaming
- 🔵 **MangoHud / Gamescope** con la paleta Material You activa. → [[MangoHud y Gamescope con paleta Material You]]
- 🔵 **Tema dinámico para Discord (Vencord)** y navegador. → [[Tema dinámico para Discord (Vencord) y navegador]]
- 🔵 **GameMode Activator:** al lanzar un juego, apagar widgets pesados y fijar luces de concentración. → [[GameMode Activator]]

### 💻 Portátil y movilidad
- 🔵 **Cambio automático de perfil de energía** (refresco a 60 Hz, luces off, `auto-cpufreq`). → [[Cambio automático de perfil de energía en portátil]]
- 🔵 **Gestos táctiles avanzados** en el touchpad. → [[Gestos táctiles avanzados en el touchpad]]

### 🔬 Hardware por descifrar
- 🔵 Lectura de batería 2.4 GHz del Akko sin EMA (sniff del handshake que fuerza frame fresco).
- 🔵 LED del cuerpo del ratón K7 Ultra.
- 🔵 Lienzo per-key del Akko por **cable** (por 2.4 GHz congela el teclado). Ver `hardware/akko-5075b-plus/`.

---

## 🔨 En curso ahora mismo

![[Backlog.base#🔨 En curso]]

## 🎯 Pendiente (por prioridad)

![[Backlog.base#🎯 Hoy]]

## 🆕 Actividad reciente de los agentes

![[Backlog.base#🆕 Reciente]]

## ✅ Terminado

![[Backlog.base#✅ Hechas]]

---

## 📓 Bitácora de sesiones

*Los agentes añaden una línea por sesión, lo más reciente arriba.*

- **2026-08-29 · Claude** — Sistema de Backlog del vault: carpeta `Backlog/`, `Backlog.base`
  con 7 vistas y esta página. Semilla con el trabajo reciente + el Roadmap accionable.
- **2026-08-29 · Claude** — Convergido a `main` (`9b8d78f`): running-pulse v2 + sonidos de
  notificaciones + backlog del vault. Shell reiniciado y verificado, sonidos activos.
- **2026-08-29 · Claude** — Sonidos de notificaciones de agentes: sonido al iniciar /
  completar / fallar, 4 paletas (`system` + 3 de Kenney CC0), CLI `agent-notify sound-set`.
  Paleta activa: `kenney-glass`.
- **2026-08-29 · Claude** — *Running pulse* v2 del pip: aro palpitante mientras el agente
  trabaja + halo neón solo en el contorno; reproducibilidad de los hooks de Claude Code
  en `install.sh`.
- **2026-08-29 · Claude** — Fix: el teclado Akko reporta transporte USB al cargar por
  cable; fix de la bandera de carga atascada en 2.4 GHz.
- **2026-08-29 · Claude** — Auto-intercepción de las notificaciones nativas de Antigravity
  y Claude hacia el pipeline enriquecido de agentes.
- **2026-08-27 · Gemini + Claude** — Notificaciones de agentes en el pip del workspace
  (v1): CLI `agent-notify`, toasts enriquecidos, halo de acento, tarjeta popout.

---

### Fijar esta nota como pantalla de inicio

Para que Obsidian la abra al arrancar: **Ajustes → Plugins de la comunidad → Explorar →
«Homepage»** (instalar y activar) → en sus opciones, *Homepage* = `🎯 Hoy`. Mientras
tanto está en **Marcadores** (barra lateral).
