---
tags: [tarea-agente, gemini, hardware, rgb, bateria, validacion]
para: Gemini
de: Claude
creado: 2026-08-27
estado: pendiente
requiere: Alberto presente para mirar los LEDs
---

# Gemini · Validación de hardware — motor `battery-lighting`

> **Eres el agente `hw-validation`.** El motor backend está terminado y con 48 tests que
> pasan, pero **nada se ha probado contra los periféricos reales**. Tu trabajo es
> ejecutar las pruebas con hardware, con Alberto delante mirando las luces, y anotar qué
> funciona y qué no. **No programas nada** — solo ejecutas, observas y documentas. Si algo
> falla, escribes un informe preciso para que Claude arregle `rgb/battery-lighting`.

## 1. Contexto

- Rama: `feat/battery-lighting-engine` (en `origin`). Haz `git fetch && git checkout feat/battery-lighting-engine`.
- Diseño: `docs/superpowers/specs/2026-08-27-battery-lighting-engine-design.md`.
- El script: `rgb/battery-lighting`. Efectos y protocolo: `docs/HARDWARE_PROTOCOLS.md` §1 (Akko) y §2 (MCHOSE base).

## 2. Instalar (sin activar el daemon todavía)

```bash
cp rgb/battery-lighting ~/.local/bin/battery-lighting && chmod +x ~/.local/bin/battery-lighting
~/.local/bin/battery-lighting --dump          # debe imprimir JSON con telemetría real de las 3 baterías
```
Anota los niveles que reporta y compáralos con lo que sabes que tienen los dispositivos.
Si algún `connected` es `false` con el dispositivo encendido → problema de telemetría, anótalo.

## 3. Pruebas de efectos (`--apply`, una por una, Alberto mira)

`~/.config/caelestia/battery-lighting.json` aún no existe: `--apply` usa las reglas
sembradas por defecto (`akko-charging`, `akko-low`, `mouse-charging`, `mouse-low`).

Para cada comando: ejecútalo, Alberto describe lo que ve, tú anotas **efecto esperado vs
efecto real**. Entre pruebas, `~/.local/bin/battery-lighting --clear` para volver al tema.

| Comando | Esperado |
|---|---|
| `battery-lighting --apply akko-charging` | Teclas: relleno tipo medidor de abajo arriba según % (color rojo→ámbar→verde). Tira lateral: flujo (steady stream) en color de batería. |
| `battery-lighting --apply akko-low` | Teclas **y** tira lateral: rojo en respiración. |
| `battery-lighting --apply mouse-low` | Anillo de la base MCHOSE: rojo en respiración. |
| `battery-lighting --apply mouse-charging` | Anillo de la base: respiración en color del tema (Material You). |
| `battery-lighting --clear` | Todo vuelve al color sólido del tema. |

### 2.1 Foco especial — mapa de coordenadas del lienzo del Akko

El efecto **medidor** en las teclas usa `AKKO_KEY_ROWS` en `rgb/battery-lighting` (~línea
286), que es un **mapa parcial y SIN validar** sacado de `docs/HARDWARE_PROTOCOLS.md §1.G`.
Al probar `--apply akko-charging`, observa con cuidado:
- ¿Se encienden filas completas de abajo arriba, o teclas sueltas / desordenadas / filas equivocadas?
- ¿La fila de abajo (Ctrl/Alt/Espacio) es la primera en encenderse?
- Prueba a editar `~/.config/caelestia/battery-lighting.json` (créalo con `battery-lighting --tick` primero) y cambia el nivel simulado no es posible por CLI — en su lugar, si el ratón/teclado está a distinto %, se verá distinto relleno. Anota el % real y cuántas filas se encienden.

Si el mapa está mal: **NO lo arregles**. Anota exactamente qué teclas se encienden para
un % dado (haz fotos si puedes) y escríbelo en el informe. Claude ajustará `AKKO_KEY_ROWS`
o degradará el efecto a `breathing_battery`.

## 4. Prueba del daemon y la cadencia adaptativa

```bash
mkdir -p ~/.config/systemd/user
cp systemd/battery-lighting.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user start battery-lighting.service
journalctl --user -u battery-lighting -f    # dejar abierto en otra terminal
```
- Con todo descargando y por encima del umbral: el daemon hace `tick` cada **60 s** (mira los timestamps del journal). `~/.cache/battery_alerts.json` debe ser `{}`.
- **Enchufa el ratón a la base.** En el siguiente tick el daemon debe: detectar `charging`, subir la cadencia a **~3 s**, y aplicar `mouse-charging` al anillo. `battery_alerts.json` pasa a `{"mchose_base:_": {...}}`.
- **Desenchufa.** Vuelve a 60 s y el anillo vuelve al tema.
- **Cambia el wallpaper** con una alerta activa (ratón enchufado): `sync-rgb.py` NO debe pisar el anillo (sigue con el efecto de carga, no salta al color del tema).
- Prueba `rgb-notify-flash --test` con una alerta activa: al terminar el flash, la zona vuelve al **efecto de alerta**, no al tema.

Para cada punto: ✅/❌ + qué pasó.

## 5. Batería baja real (si algún dispositivo llega solo)

Si durante las pruebas algún periférico baja del 20 %: confirma que salta la notificación
de escritorio (`notify-send`, en español) **una sola vez** y que el efecto `*-low` se aplica.
Si no llega ninguno al 20 %, anótalo como «no probado».

## 6. Informe

Escribe `vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/Gemini · Validación de hardware — INFORME.md`:
- Tabla efecto por efecto: esperado / real / ✅❌.
- El hallazgo del mapa `AKKO_KEY_ROWS` (qué teclas se encienden para qué %).
- La cadencia del daemon y la coordinación con `sync-rgb` / `notify-flash`.
- Notificaciones de escritorio: ✅❌ / no probado.
- Lista de arreglos que necesita `rgb/battery-lighting` (para Claude), en orden de prioridad.

Al terminar: `systemctl --user stop battery-lighting.service` (no lo dejes activo hasta
que todo esté validado y mergeado). Avisa a Alberto.
