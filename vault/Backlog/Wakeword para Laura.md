---
fileClass: Backlog
tipo: tarea
estado: pendiente
prioridad: 2
area: agentes
origen: Alberto
esfuerzo: M
creado: 2026-09-05
flujo: "[[Asistente de voz con IA local]]"
tags:
  - backlog
---

# Wakeword para Laura

Añadir un **disparador por voz** ("Laura", o la palabra que se decida) como alternativa
al atajo de teclado actual, sin sustituirlo. Fase 5 ya prevista en
[[Asistente de voz con IA local]] §2.6 — esta nota es la **guía de ejecución paso a
paso** para implementarla, pensada para seguirse sin tener que investigar nada más.

> [!info] Hardware del portátil: GPU con **6 GB de VRAM** (~GTX/RTX 1060). La solución
> recomendada aquí es **CPU-only y minúscula** (no compite por VRAM con Whisper/Ollama).

---

## 1. Qué opciones hay y cuál usar

| Opción | Local | VRAM | Coste | Entrenar palabra propia |
|---|---|---|---|---|
| **openWakeWord** (recomendado) | Sí, 100% | 0 (CPU, modelo de ~1 MB) | Gratis, código abierto | Sí, con datos sintéticos (sin grabarse) |
| Porcupine (Picovoice) | Inferencia sí, entrenamiento pasa por su nube | 0 | Gratis con cuenta + límites | Sí, más fácil pero depende de su servicio |
| Whisper siempre escuchando | Sí | Alta (modelo cargado permanente) | Gratis | No aplica — ya descartado en la nota madre |

**Recomendación: openWakeWord.** Es la única opción 100% local y sin cuenta externa,
coherente con tu preferencia de modelos locales, y el consumo es despreciable (corre en
CPU, dejando la GPU libre para Whisper/Ollama cuando el LLM entra en acción). La
palabra "Laura" no viene preentrenada, así que hay que entrenar un modelo propio — es
un proceso ya resuelto por el proyecto (genera cientos de muestras sintéticas con un
TTS en vez de grabarte repitiendo la palabra), no investigación desde cero.

---

## 2. Qué instalar

```bash
# Entorno del daemon (el mismo venv/conda que usa laurad.py)
pip install openwakeword

# Generador de muestras sintéticas de la palabra clave (para entrenar)
git clone https://github.com/rhasspy/piper-sample-generator ~/tools/piper-sample-generator
cd ~/tools/piper-sample-generator
pip install -r requirements.txt
# Descarga el modelo generador base (instrucciones en el README del repo, es un .onnx)
```

`openwakeword` en su primer uso descarga automáticamente sus modelos base de
verificación de voz/ruido (VAD interno + modelo de "habla general") — necesita conexión
a internet la primera vez, luego funciona offline.

---

## 3. Entrenar el modelo "Laura"

1. **Generar muestras sintéticas** de la palabra "Laura" con `piper-sample-generator`,
   variando voces/acentos/velocidad (el propio repo trae el script para generar cientos
   de variantes automáticamente — no hace falta grabar nada a mano). Objetivo: 500-1000
   clips cortos.
2. **Aumentar el dataset** con ruido de fondo y reverberación: openWakeWord distribuye
   un notebook/script de entrenamiento (`openwakeword/train.py` en su repo,
   `https://github.com/dscripka/openWakeWord`) que ya incluye la mezcla con datasets de
   ruido ambiental — sigue su notebook de "Entrenar un modelo nuevo" tal cual, solo
   cambiando la carpeta de muestras positivas por las tuyas de "Laura".
3. **Entrenar y exportar** el modelo resultante a ONNX. Guardarlo en
   `assistant/models/laura.onnx` (ruta ya anticipada en la nota madre).
4. Verificación rápida: el propio notebook de openWakeWord da una curva de
   precisión/recall sobre un set de validación — con eso puedes fijar ya un umbral de
   partida antes de probarlo en vivo (paso 6).

> Este paso 3 es el único que requiere GPU puntualmente para entrenar más rápido (unos
> minutos); si prefieres evitarlo, el notebook también corre en CPU, solo que más lento.
> Una vez entrenado, el modelo `.onnx` resultante es el que corre luego en CPU a diario.

---

## 4. Integrar en `laurad.py`

Añadir una clase `WakeListener` (nombre ya anticipado en la nota madre) que:

- Abre un stream de micrófono continuo a 16 kHz mono (con `sounddevice`, igual que ya
  usa el resto del daemon).
- Por cada bloque de audio (chunks de ~80 ms, como recomienda openWakeWord), llama a
  `openwakeword.Model(wakeword_models=["assistant/models/laura.onnx"])` y compara el
  score contra un umbral configurable.
- Al superar el umbral, dispara el **mismo evento IPC** que hoy dispara el atajo de
  teclado (el "toggle" que arranca VAD → Whisper → LLM → TTS) — no un camino nuevo en
  paralelo, sino el mismo punto de entrada.
- **Se pausa a sí misma** mientras el daemon está escuchando/hablando (durante el ciclo
  VAD/Whisper/TTS), para no re-disparar con su propia voz de salida ni consumir CPU de
  más durante la conversación activa. Reanuda al volver a reposo.

Config nueva en `assistant/config.toml`:

```toml
[wake]
enabled = false        # empieza desactivado hasta que se pruebe y ajuste el umbral
model_path = "assistant/models/laura.onnx"
threshold = 0.5         # ajustar en el paso 6 según falsos positivos/negativos
device = "default"      # índice o nombre del micrófono si hace falta fijarlo
```

`laurad.py` arranca `WakeListener` en un hilo aparte al iniciar el daemon **solo si**
`wake.enabled = true` — así el atajo de teclado sigue funcionando exactamente igual
tanto si el wakeword está activo como si no.

---

## 5. Arranque

No hace falta tocar `laura.service` (systemd `--user`): el `WakeListener` vive dentro
del mismo proceso `laurad.py` que ya arranca con el servicio, simplemente añade un hilo
más si `wake.enabled = true`. Un `systemctl --user restart laura` tras activarlo en el
`config.toml` es suficiente.

---

## 6. Cómo probarlo

1. **Prueba aislada primero** (antes de tocar el daemon): un script suelto
   `assistant/test_wakeword.py` que solo abra el micro, corra el modelo y **imprima el
   score en vivo** cada vez que hables cerca. Di "Laura" varias veces y observa el pico
   de score frente al ruido de fondo — eso te da el umbral real a poner en `config.toml`
   (normalmente entre 0.4 y 0.6, pero depende del modelo entrenado).
2. **Actívalo en el daemon**: `wake.enabled = true`, reinicia el servicio, di "Laura" y
   confirma que se abre el mismo estado de "escuchando" que con el atajo (compruébalo
   igual que ya pruebas el resto: mirando los eventos del socket, o simplemente que
   Laura responda).
3. **Prueba de falsos positivos**: ten una conversación normal cerca del micro sin decir
   "Laura" y confirma que no se dispara sola.

---

## 7. Cómo depurar si no responde

- **No detecta nunca / score siempre bajo:** primero confirma con `test_wakeword.py`
  que el score sube al decir la palabra — si ni ahí sube, el problema es el modelo
  entrenado (dataset de muestras insuficiente/poco variado) o el micrófono equivocado
  (revisa `sounddevice.query_devices()` y fija `wake.device`), no la integración.
- **Se dispara solo / falsos positivos:** sube el `threshold` en `config.toml`
  gradualmente (pasos de 0.05) hasta que desaparezcan; si persiste, revisa que el
  `WakeListener` se esté pausando de verdad durante la salida de TTS de Laura (si no,
  se está oyendo a sí misma).
- **Tarda mucho en reaccionar:** revisa el tamaño de bloque de audio (chunks
  demasiado grandes añaden latencia); openWakeWord está pensado para bloques pequeños
  (~80 ms) y sigue siendo barato en CPU a ese ritmo.
- **Consume CPU de más en reposo:** confirma que solo hay **un** hilo de inferencia
  activo (no se debe relanzar el modelo por cada bloque desde cero) y que Whisper no
  está también escuchando en paralelo — el wakeword debe ser el único proceso "siempre
  encendido"; Whisper solo arranca tras el disparo.
