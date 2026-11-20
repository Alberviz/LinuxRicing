---
fileClass: Backlog
tipo: tarea
estado: en-curso
prioridad: 2
area: agentes
origen: Alberto
esfuerzo: L
creado: 2026-10-05
flujo: "[[Asistente de voz con IA local]]"
tags:
  - backlog
---

# Seguir avanzando en Laura

Evolucionar y consolidar a **Laura** (el asistente de voz con IA local en `assistant/`) para que sea más natural, autónoma y esté profundamente integrada en el flujo de trabajo diario. Laura debe dejar de depender exclusivamente de atajos de teclado manuales, responder a su palabra de activación y adquirir un control exhaustivo sobre las tareas de todos los repositorios y el control general del sistema.

> [!abstract] Flujo madre y notas técnicas relacionadas
> - Nota arquitectónica principal: [[Asistente de voz con IA local]]
> - Guía de entrenamiento e integración del disparador: [[Wakeword para Laura]]
> - Acceso y edición de tareas: [[Laura gestiona las tareas (crear y modificar)]] y [[Sistema unificado de tareas]]
> - Escalada inteligente a modelos superiores: [[Laura puede abrir sesiones de gemini para todo lo que no sabe hacer]]

---

## 🎯 Subtareas de desarrollo

### 1. 🎙️ Poner la Wake Word ("Laura")
Habilitar la activación por voz continua y ligera sin depender únicamente del atajo de teclado (`Super+A`), manteniendo un consumo nulo de VRAM y mínimo de CPU:

- [ ] **Entorno y herramientas:** Instalar dependencias en el entorno del asistente (`openwakeword`, `piper-sample-generator`).
- [ ] **Generación de dataset sintético:** Generar entre 500 y 1000 muestras de la palabra clave "Laura" con variaciones acústicas y de velocidad.
- [ ] **Entrenamiento y exportación:** Entrenar el modelo con aumento de ruido ambiental y exportarlo a ONNX en `assistant/models/laura.onnx` (seguir la guía en [[Wakeword para Laura]]).
- [ ] **Script de prueba y umbral:** Crear `assistant/test_wakeword.py` para visualizar scores en vivo y ajustar el umbral óptimo (ej. 0.45 - 0.55).
- [ ] **Integración en el daemon:** Implementar la clase `WakeListener` en `laurad.py` con captura de audio en 16 kHz en un hilo desacoplado.
- [ ] **Pausa inteligente y anti-eco:** Pausar automáticamente el listener mientras Laura está hablando (TTS) o procesando para evitar auto-disparos o bucles.
- [ ] **Configuración:** Añadir bloque `[wake]` en `assistant/config.toml` (`enabled`, `model_path`, `threshold`, `device`).

---

### 2. 📋 Mucho más control de las tareas
Permitir a Laura ser la interfaz vocal principal para gestionar el día a día y la productividad en todo el ecosistema de repositorios:

- [ ] **Integración profunda con `tasks-index`:** Extender las herramientas de `assistant/tools.py` (`listar_tareas`, `crear_tarea`, `cambiar_estado`) con filtrado inteligente por repo (`LinuxRicing`, `Universidad`, `Gym`, `Minecraft`).
- [ ] **Comprensión contextual de lenguaje natural:**
  - *"Laura, ¿qué tengo pendiente para hoy?"* (lectura priorizada de `🎯 Hoy`).
  - *"Laura, apunta repasar apuntes en Universidad con prioridad alta"*.
  - *"Laura, pon la tarea del agujero negro en curso"*.
  - *"Marca como hecha la tarea de..."*.
- [ ] **Sincronización con Google Tasks:** Conectar con `widgets/gtasks` y sincronización bidireccional ([[Sync bidireccional con Google Tasks]]).
- [ ] **Resumen matutino y proactividad:** Comando de voz para resumen rápido del backlog y distribución de carga al comenzar el día.

---

### 3. 🖥️ Control general del sistema y del entorno ("control de todo")
Ampliar drásticamente las herramientas (`tools.py`) y facultades de Laura para manipular el escritorio y el hardware:

- [ ] **Gestión de ventanas y workspaces:**
  - Mover ventanas activas a otros workspaces, organizar cuadrículas o enfocar ventanas específicas mediante `hyprctl`.
  - Consultar qué aplicaciones o ventanas están abiertas por workspace.
- [ ] **Modos globales y perfiles de energía:**
  - Activar/desactivar por voz el **Modo Cine** (atenuación de luces, mute de notificaciones, pantalla completa).
  - Activar/desactivar el **Modo No Molestar** y el **Modo Servidor** (`caelestia-server-mode`).
  - Cambiar perfiles energéticos (`power-saver`, `balanced`, `performance`).
- [ ] **Periféricos e iluminación:**
  - Control de perfiles RGB y escenas de 1 clic (tiras LED, ventiladores vía OpenRGB / `argb-wave`).
  - Consulta de batería de teclado Akko y ratón MCHOSE K7 Ultra.
- [ ] **Escalada a Gemini (CLI Antigravity `agy`):**
  - Fusionar y consolidar la rama `feat/laura-gemini-escalation` en `main`.
  - Capacidad para que Laura ejecute consultas complejas o genere código delegando a Gemini en segundo plano cuando el LLM local no dé abasto.

---

### 4. ⚡ Optimización, huella de memoria y estabilidad
- [ ] **Carga perezosa (lazy-load):** Descargar modelos pesados (Whisper/Torch) a RAM/disco tras periodos de inactividad para que el daemon en reposo pase de ~3 GB a <150 MB.
- [ ] **Reinicio limpio y telemetría:** Control de estado reactivo mediante `systemctl --user status/restart laura`.
