# Laura Holo — Visor Emergente de Archivos Holográfico

**Laura Holo** es el subsistema de presentación visual para el asistente de voz **Laura** y el entorno de escritorio **Caelestia Shell**. Permite listar y previsualizar archivos en paneles holográficos flotantes sobre el escritorio mediante órdenes de voz naturales o interacción con ratón, e integrarlos directamente con el sistema de transferencia **Warp** hacia dispositivos móviles.

---

## 🏗️ Arquitectura del Sistema

```
 [Usuario (Voz / Atajo)]
           │
           ▼
     [Laura Daemon]
     ├── holo_preview.py  ─── Generación de miniaturas (Pillow, pdftoppm, ffmpegthumbnailer)
     ├── holo.py (Escena) ─── Estado reactivo, numeración 1..12, TTL 600s, RLock
     └── tools/holo.py    ─── mostrar_archivos, abrir, cerrar_holo, warp(numero=N)
           │
           │ (Socket UNIX EventBus: {"type":"holo", "op": ...})
           ▼
   [Caelestia Shell (QML)]
     ├── HoloState.qml    ─── Singleton receptor de eventos y puente de control
     ├── HoloLayer.qml    ─── Ventana Wayland Overlay con velo, escaneo y gestor de ciclo de vida
     ├── HoloPlacer.js    ─── Colocación orgánica espacial sin colisiones
     ├── HoloLinks.qml    ─── Hilos Bezier punteados entre lista y visores
     ├── HoloPanel.qml    ─── Chasis holográfico (cristal, scanlines, rayo, drag-to-mobile)
     └── Contenidos       ─── HoloList, HoloImage, HoloPdf, HoloMedia, HoloText, HoloOther
```

### Contrato de Eventos (Python ⇄ QML)
Toda la sincronización viaja por el bus de eventos de Laura (`laura/events.py`):
```json
{
  "type": "holo",
  "op": "snapshot|list|open|close|select|sent|page|clear",
  "items": [
    {
      "n": 1,
      "ruta": "/home/alberviz/Descargas/foto.png",
      "nombre": "foto.png",
      "tipo": "imagen",
      "tamano": 102400,
      "mtime": 1731170000.0,
      "enviado": false
    }
  ],
  "paneles": [
    {
      "id": "lista",
      "kind": "lista",
      "titulo": "Descargas",
      "item_n": null,
      "payload": { "items": [...] }
    },
    {
      "id": "v1",
      "kind": "visor",
      "titulo": "foto.png",
      "item_n": 1,
      "payload": { "tipo": "imagen", "src": "/path/to/foto.png", "w": 800, "h": 600 }
    }
  ],
  "seleccionado": 1,
  "panel": { ... },
  "ids": ["v1"]
}
```

---

## 🎙️ Comandos de Voz y Lenguaje Natural

| Intención | Ejemplos de frases | Herramienta invocada |
|---|---|---|
| **Listar / Buscar** | *«Laura, lístame las descargas»*<br>*«¿Qué hay en Documentos?»*<br>*«Busca el pdf de redes»* | `mostrar_archivos(carpeta="...", consulta="...")` |
| **Abrir visores** | *«Ábreme la 1 y la 2»*<br>*«Enséñame esa captura»*<br>*«Abre el informe»* | `abrir(numeros=[1, 2])` |
| **Enviar por Warp** | *«Envía la 2 al móvil»*<br>*«Manda esa al móvil»* | `warp(accion="archivo", numero=2)` *(o seleccionado)* |
| **Cerrar** | *«Cierra la 2»*<br>*«Cierra eso»*<br>*«Cierra todo»* | `cerrar_holo(numeros=[2], todo=true)` |

> [!NOTE]
> Cuando hay archivos en pantalla, el system prompt del LLM recibe la línea de contexto activa generada por `escena().contexto()`. Esto permite resolver referencias relativas como *«esa»*, *«el pdf»* o *«la primera»* sin ambigüedad.

---

## 🖱️ Controles e Interacción con Ratón y Teclado

- **Imágenes (`HoloImage`)**:
  - Gira la rueda del ratón o haz scroll con touchpad sobre la imagen para hacer zoom interactivo (**1× a 5×**) centrado en la posición del cursor.
  - Arrastra con el ratón cuando hay zoom para desplazarte por la imagen.
  - **Doble clic**: restablece el zoom instantáneamente a 1×.
- **Documentos PDF (`HoloPdf`)**:
  - Gira la rueda del ratón para avanzar o retroceder de página (`pág N/M`).
  - Incorpora un temporizador debounce de 250 ms para no sobrecargar el renderizado de Poppler.
- **Texto y Código (`HoloText`)**:
  - Soporta Markdown renderizado o texto monoespaciado (`JetBrains Mono`).
  - Selección de texto habilitada con ratón y scroll vertical fluido.
- **Multimedia (`HoloMedia`)**:
  - Vídeo con póster inicial y `VideoOutput`, o audio con gráfico de onda reactivo.
  - Clic en el cuerpo: conmutar Reproducción / Pausa.
  - Barra de progreso interactiva inferior.
- **Selección («esa»)**:
  - Clic izquierdo sobre cualquier visor lo selecciona y resalta su halo exterior (`HoloState.seleccionar`).
- **Gesto enviar al móvil (Warp)**:
  - Arrastra cualquier panel por su cabecera hacia arriba (`y < 60 px`); se activará el cartel holográfico *«Suelta para enviarlo al móvil»*. Al soltar, se despacha por Warp.
- **Cierre**:
  - Clic en el botón `close` de la cabecera.
  - **Clic derecho** en cualquier panel para cerrarlo de golpe.
  - **Tecla `Escape`**: cierra la escena holográfica completa.

---

## 🛠️ Archivos del Proyecto

### Backend (Python)
- [`assistant/laura/holo_preview.py`](file:///home/alberviz/proyectos/LinuxRicing/assistant/laura/holo_preview.py): Detección MIME, generación de PNGs en `$XDG_RUNTIME_DIR/laura-holo`, paginado de PDF con `pdftoppm` y limpieza automática de caché (200 MB máx).
- [`assistant/laura/holo.py`](file:///home/alberviz/proyectos/LinuxRicing/assistant/laura/holo.py): Estructura `Escena`, modelo `Item`, contexto para el LLM y despachador de control (`holo-*`).
- [`assistant/laura/tools/holo.py`](file:///home/alberviz/proyectos/LinuxRicing/assistant/laura/tools/holo.py): Tools `mostrar_archivos`, `abrir`, `cerrar_holo`.
- [`assistant/laura/tools/warp.py`](file:///home/alberviz/proyectos/LinuxRicing/assistant/laura/tools/warp.py): Integración del parámetro `numero` y resolución de «esa».
- [`assistant/tests/test_holo_preview.py`](file:///home/alberviz/proyectos/LinuxRicing/assistant/tests/test_holo_preview.py), [`test_holo.py`](file:///home/alberviz/proyectos/LinuxRicing/assistant/tests/test_holo.py), [`test_tools_holo.py`](file:///home/alberviz/proyectos/LinuxRicing/assistant/tests/test_tools_holo.py): Suite de pruebas unitarias exhaustiva.

### Frontend (Quickshell / QML)
- [`configs/quickshell/caelestia/modules/assistant/HoloState.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/assistant/HoloState.qml): Singleton de estado e IPC.
- [`configs/quickshell/caelestia/modules/holo/HoloLayer.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloLayer.qml): Capa Overlay / Top con velo y orquestador de ciclo de vida.
- [`configs/quickshell/caelestia/modules/holo/HoloPanel.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloPanel.qml): Chasis del holograma (cristal oscuro, halo del color del acento, escaneo, animaciones y esquinas HUD).
- [`configs/quickshell/caelestia/modules/holo/HoloPlacer.js`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloPlacer.js): Cálculo de posición orgánica y tamaños en función de la pantalla.
- [`configs/quickshell/caelestia/modules/holo/HoloLinks.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloLinks.qml): Conectores curvilíneos punteados entre filas e hijos.
- [`configs/quickshell/caelestia/modules/holo/HoloGeo.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloGeo.qml): Medidas y constantes geométricas compartidas.
- [`configs/quickshell/caelestia/modules/holo/HoloList.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloList.qml): Vista de lista numerada.
- [`configs/quickshell/caelestia/modules/holo/HoloImage.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloImage.qml): Visor de imágenes con zoom.
- [`configs/quickshell/caelestia/modules/holo/HoloPdf.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloPdf.qml): Visor de PDF con paginador.
- [`configs/quickshell/caelestia/modules/holo/HoloMedia.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloMedia.qml): Reproductor de audio/vídeo.
- [`configs/quickshell/caelestia/modules/holo/HoloText.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloText.qml): Visor de texto / markdown / código.
- [`configs/quickshell/caelestia/modules/holo/HoloOther.qml`](file:///home/alberviz/proyectos/LinuxRicing/configs/quickshell/caelestia/modules/holo/HoloOther.qml): Fallback con botón de apertura externa (`xdg-open`).

---

## 🗂️ Gestión de archivos (borrar, mover, renombrar)

Sobre la lista que se ve en pantalla (o la carpeta que se acaba de listar):

| Frase | Herramienta |
|---|---|
| «borra la 2» · «elimina esas» | `borrar_archivos` (papelera, **siempre con confirmación**) |
| «mueve la 3 a Universidad» | `mover_archivos` (confirma si son más de 5) |
| «renombra la 1 a factura.pdf» | `renombrar_archivo` |
| «crea una carpeta que se llame Facturas» | `crear_carpeta` |
| «deshaz» | `deshacer_archivos` |

**Flujo:** la tool solo crea un *plan*; si requiere confirmación aparece el panel «confirmar»
(archivos afectados, tamaño total, **Cancelar / Borrar**) y Laura pregunta por voz. Vale decir
«sí»/«no» **o** pulsar el botón, lo que llegue primero; el plan caduca a los 60 s (si contestas
tarde, un «sí» suelto aún lo resuelve). Al ejecutarse, las filas se van, aparece la papelera
en la esquina y la carpeta se vuelve a listar (los números cambian).

- **Papelera:** todo va a `~/.local/share/Trash` (nunca `rm`). El diario
  `~/.local/state/laura/archivos.jsonl` permite «deshaz» incluso tras reiniciar.
- **Alcance** (`[archivos]` en `assistant/config.toml`): Descargas, Documentos, Escritorio,
  Imágenes, Vídeos, Música y `~/proyectos`. Nunca ocultos, `.git`, `vault`, ni enlaces que
  salgan de esas carpetas. Máximo 50 operaciones por plan.
- **Código:** `assistant/laura/archivos.py` (motor), `confirmar_archivos.py` (voz/panel),
  `tools/archivos.py`, y en QML `HoloConfirm.qml`.
- **Demo sin daemon:** `qs -c caelestia ipc call holo demoConfirm borrar` (o `mover`) y
  `ipc call holo demoResolver true|false`.
- Spec y plan: `docs/superpowers/specs/2026-11-09-laura-archivos-design.md`,
  `docs/superpowers/plans/2026-11-09-laura-archivos-fase1.md`.

## 🧪 Pruebas y Diagnóstico

### Modo Demostración Rápido (sin dependencias del daemon)
Para comprobar visualmente la capa y los componentes en vivo en Quickshell:
```bash
# Abrir lista y 4 visores de prueba (imagen, PDF, markdown, comprimido)
qs -c caelestia ipc call holo demo

# Limpiar y cerrar la escena
qs -c caelestia ipc call holo clear
```

### Ejecutar tests unitarios de Python
```bash
cd assistant && python3 -m pytest -q tests/test_holo*.py tests/test_tools_holo.py
```

### Sincronización del Shell de Quickshell
Tras cualquier modificación en archivos QML del módulo:
```bash
cp -r configs/quickshell/caelestia/modules/holo ~/.config/quickshell/caelestia/modules/
cp configs/quickshell/caelestia/modules/assistant/HoloState.qml ~/.config/quickshell/caelestia/modules/assistant/
caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d
```
Verificar que la salida muestre:
```
INFO: Configuration Loaded
```

---

## 📌 Estado Actual y Pasos Siguientes (Tarea 7)

- **Completadas con éxito**: Tareas 1 a 6 del plan (`docs/superpowers/plans/2026-11-09-laura-holo.md`).
- **Pendiente para la sesión siguiente (Tarea 7)**:
  1. **Frases de evaluación**: Añadir el grupo `# ---------- hologramas ----------` en [`assistant/eval/frases.toml`](file:///home/alberviz/proyectos/LinuxRicing/assistant/eval/frases.toml).
  2. **Evaluación de LLM**: Ejecutar `cd assistant && python3 eval/run.py` para verificar que `qwen3:4b-instruct` mantiene la precisión (≥ 7/9 en holo).
  3. **Reinicio de daemon en vivo**: `systemctl --user restart laura` y prueba de voz integral con descargas locales.
  4. **Revisión y Commit**: El orquestador revisa los cambios no commiteados y commitea la Tarea 6.
  5. **Merge**: Merge de la rama `feat/laura-holo` a `main`.
