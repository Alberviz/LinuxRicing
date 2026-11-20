# Wake word de Laura: análisis de falsos positivos, nombre nuevo y plan de mejora

Fecha: 2026-11-20. Solo análisis: no se ha cambiado código, config, servicios ni git.

## 1. Estado actual

**Detección** (`assistant/laura/wake.py`): `WakeListener` se suscribe al micro compartido (`MIC`),
trocea en ventanas de 80 ms (1280 muestras, 16 kHz) y pasa cada una a openWakeWord con un único
modelo propio, `models/laura.onnx`. Dispara cuando `racha >= patience` ventanas seguidas tienen
`score >= threshold` y han pasado `cooldown` segundos desde el último disparo. Al disparar llama a
`fire("centro")`, que abre `cycle()` en **modo centro** (conversación de hasta `max_turns = 6` turnos).
Pausa/reanuda: `pause()` descarta el audio (buf y racha a cero); `resume()` hace `oww.reset()`.
Se pausa durante cada ciclo (`before`/`after` de `daemon.py`), en `modo juego` y mientras habla Laura.

**Config `[wake]`** (sin cambios locales respecto a HEAD): `threshold = 0.8`, `patience = 3`
(= 240 ms sobre el umbral), `cooldown = 3.0`, `model = models/laura.onnx`, frase **«Laura despierta»**.
Historial: el commit `d8b0fb0` subió a 0.9/4 «saltaba con conversación de fondo»; luego se volvió a
0.8/3 porque «0,9+4 no le oía ni a propósito». Es decir: ya se ha jugado con el umbral y no hay margen.

**Modelo** (`assistant/wake_train/`, **sin commitear**: `models/` y `wake_train/` salen como `??` en git):
- Arquitectura: audio, melspectrograma, embeddings congelados de Google (los trae openWakeWord),
  MLP de 2 capas x 128 sobre las últimas 16 ventanas (16x96, ~2 s). Se exporta a ONNX (840 KB).
- `sinteticos.py`: 1808 positivos y 2581 negativos TTS (voces Piper es + mezclas Kokoro), más 495
  «solo_laura». Negativos parecidos: «Aurora», «ahora», «Lara», «Clara»...
- `grabar.py`: voz de Alberto = **35 positivos**, **20 «casi»** (Laura sola), **90 s de habla**
  (`alb_habla_00.wav`) y **45 s de ambiente**.
- `entrenar.py`: aumento (reverb, filtros, ruido, murmullo), cada positivo cortado antes de
  «despierta» como negativo, 150 000 ventanas de `validation_set_features.npy` de openWakeWord como
  negativos, peso de negativos creciente (1 a 30), 40 épocas. Medida de falsos/h con la otra mitad
  de ese set: **~0,2/h**.
- Fecha del modelo: 9 nov. Es la única versión entrenada.

## 2. Datos medidos (journal de `laura.service`, ventana `-3 days`; el journal empieza el 19 nov 00:43)

- **18 disparos en total**: 0 el 19 nov, 4 el 20 nov de madrugada (01:48-02:18), 14 el 20 nov entre
  15:48 y 17:35 (**~3,8 disparos/h** esa tarde; ver el hueco más abajo). El 19 nov el wake estuvo activo
  ~7 h sin un solo disparo, así que el problema es muy dependiente del entorno (charla larga en la
  habitación/llamada/TV el 20 por la tarde).
- **Puntuaciones**: mín 0,81, mediana 0,955, máx 1,00. Distribución: `>=0,99`: 6; 0,95-0,98: 6;
  0,90-0,94: 3; `<0,90`: 3. **No son disparos marginales**: el modelo está *seguro* (la mitad `>=0,95`).
  Subir el umbral a 0,9 solo recortaría 3 de 18; para quitar la mayoría habría que ir a 0,99+, y a esa
  altura ya no oye a Alberto (comprobado en el commit anterior).
- **Qué pasó tras cada disparo** (cruzando con `tú:` / «nada que transcribir» hasta el siguiente wake):
  - 12 disparos sin transcripción útil (`(nada que transcribir)`: 5, ciclo cerrado en silencio o por
    «Para»/stop sin ningún `tú:`: 7). Falso positivo casi seguro (o Alberto dijo «Laura» sin más).
  - 4 con transcripción que parece **charla ambiente, no una orden** («Te da un comentario mucho como
    ver», «¿En qué puto?», «que me acabo contigo, vale…», «Y obviamente te olvido de las cosas…»).
    En esos casos Laura contestó al aire (p. ej. «Ponme el telegravio en la tele», «Apunto que Eva la
    siente»), o sea **el falso positivo además actúa**.
  - Solo 2 parecen reales: 15:48 «activa el nuevo juego, Laura» y 01:56 «¡Hasta la próxima!» (probable
    prueba/despedida).
  - **Estimación: ~15-16 de 18 (≈85-90 %) son falsos positivos.** Cuando hay transcripción casi
    siempre aparece «Laura» como palabra hablada («Adiós Laura», «activa..., Laura»), pero nunca
    «despierta»: sospecha fuerte de que el modelo dispara con **«Laura» sola** (o parecidas).
- **Eco/bucle**: a las 16:33:08-18 aparecen cuatro `tú: Adiós` seguidos cada ~3,2 s tras «¡Adiós, Laura!»
  y poco después `atajo con Laura hablando: corto la voz` (16:33:19). Parece un reinicio en bucle por
  voz de Laura/eco (un ciclo que se vuelve a abrir), conviene revisarlo aparte (barge-in / `on_barge`).

**Test offline del modelo actual** (script en el scratchpad, solo lectura, CPU), sobre los propios datos de entrenamiento:

| Conjunto | Resultado |
|---|---|
| 35 positivos de Alberto | 35/35 con pico `>=0,8` (media de picos 0,99) |
| 20 «casi» de Alberto («Laura», «Laura, ven»...) | **3/20 pasan 0,8** (media de picos 0,17) |
| 100 «solo_laura» sintéticos | 0/100 pasan 0,8 |
| 90 s de habla normal de Alberto (¡incluida en el entrenamiento!) | **pico 0,99, 2 ventanas `>=0,8`** |
| 45 s de ambiente | pico ~0 |

Es decir: incluso sobre material que ha visto entrenando, el modelo sigue disparando con la voz de
Alberto diciendo «Laura» y con trozos de su habla. Con audio no visto (la tarde del 20) es peor.

## 3. Causas probables (ordenadas por peso)

1. **Casi no hay negativos reales en español de Alberto**: ~90 s de habla + 20 «casi». El resto son
   TTS (distribución distinta a un micro real) y las 11 h de openWakeWord, que son **inglés/ruido
   variado**. El «0,2 falsos/h» se midió ahí, no sobre habla española: el número no es representativo.
   Es la causa principal y por eso falla justo al *hablar de cualquier cosa*.
2. **El modelo aprendió «Laura» más que «despierta»**: la frase larga se reduce en la práctica a su
   primera palabra (mismo patrón del «cortado»: el aumento solo enseña a rechazar el inicio cuando
   termina muy tarde en el clip). Los negativos «Laura sola» están muy sintetizados; con voz real
   fallan 3/20 y en directo hay muchos «Laura» pronunciados naturalmente (novia, conversaciones).
3. **Nombre ya compartido con el mundo real**: «Laura» es nombre propio frecuente y es el nombre de la
   novia de Alberto. Fonéticamente /láu.ra/ es corto y muy común (aura, ahora, Lara, la hora, aula).
   Un nombre así genera falsos *reales* (alguien dice «Laura») que ningún modelo puede evitar.
4. **Embeddings congelados + MLP pequeño sin segunda etapa**: con ~2 s de contexto y sin verificador,
   cada pico confuso abre un ciclo entero. Sin VAD previo ni segunda comprobación, no hay filtro de
   «¿esto era realmente el nombre?».
5. **Calibración de entrada**: en entrenamiento cada clip se normaliza a pico 0,05-0,9 y se le añade
   ruido; en directo entra el micro tal cual. Un offset de ganancia puede subir o bajar scores. No se
   puede medir sin audio real: se arregla con el modo de captura del plan (sección 5).
6. **Eco de altavoces/TV**: Laura se pausa mientras habla, pero la tele, Spotify o la voz de otras
   personas pasan al micro sin cancelación de eco. Con la TV puesta y habla española es el escenario
   probable de la tarde del 20 (3,8/h).
7. **Daño amplificado por el modo centro**: tras un falso positivo `cycle()` se queda escuchando
   hasta 6 turnos y responde a cualquier ruido que Whisper transcriba (incluidas alucinaciones). Un
   falso inofensivo se convierte en acciones de verdad.
8. **Umbral/patience**: no son la causa raíz (las puntuaciones son altas) y ya están en el límite.

## 4. Nombres propuestos

Criterios: 3+ sílabas, consonantes poco frecuentes o grupos poco habituales (f, rs, ps, ph-like),
no es palabra ni nombre frecuente del español, se dice fácil, compatible con el tono Olimpo. Se evita
«Aurora» (ya es el agente de Drive/Docs), «Hermes» (2 sílabas), «Hécate» («hace té»), «Eurídice» («dice»).

| Nombre | Sílabas | Por qué sí | Riesgo |
|---|---|---|---|
| **Perséfone** | Per-sé-fo-ne (4) | Reina del Elíseo/Inframundo: conecta con «Elysium»; grupo /rs/ y /f/ casi inexistentes juntos en el habla diaria; 4 sílabas con acento claro | Algo larga; se puede acortar a «Sefo» solo por cariño, no como wake |
| **Calíope** | Ca-lí-o-pe (4) | Musa de la voz épica («la de la hermosa voz»): perfecta para un asistente de voz; secuencia /kaˈli.o.pe/ muy rara en español común | Hiato «io» a veces se pronuncia «Calíope»/«Califope»; entrenar variantes |
| Hiperión | I-pe-rión (3-4) | Titán de la luz; /p-r/ + «ión» final marcado; muy raro en el habla | Se confunde menos que otros, pero termina como mucha palabra en «-ión» |
| Zéfiro | Zé-fi-ro (3) | Viento del oeste; /θ/ + /f/ rarísimos juntos; breve y limpio | Acento esdrújulo (hay quien dice «cefiro») |
| Prometeo | Pro-me-te-o (4) | Muy memorable (el que dio el fuego); 4 sílabas | Se parece a «prometo»: más frecuente en frases normales |
| Quimera | Qui-me-ra (3) | Criatura mítica; /kim/ + /ra/ distintivo | Palabra poco común pero existe; no es del Olimpo |
| Ariadna | A-riad-na (3) | Hilo que guía en el laberinto; /dn/ raro | Es nombre propio (poco frecuente); vocales abiertas |
| Alcíone | Al-cí-o-ne (4) | Constelación/ave de los mares; /lθ/ muy raro | Poco conocido; vocales sueltas |

**Recomendación: Perséfone y Calíope.**
1. **Perséfone**: la mejor señal acústica (consonantes distintivas, 4 sílabas) y cierra el círculo con
   «Elysium» (el Elíseo es su reino).
2. **Calíope**: la mejor historia («la voz hermosa») y también fonéticamente distinta de todo lo del
   sistema (Aurora, Instinct, Olimpo). Si hay que elegir, Perséfone por robustez acústica.

Quitar «Laura» como nombre tiene un beneficio añadido: se acaba la colisión con el nombre real de la
novia de Alberto.

## 5. Plan recomendado

**Principio:** el modelo viejo es corto, entrenó con pocos negativos reales y sin segunda etapa. El
orden con más retorno por coste es: (A) verificador con Whisper y reducir daño del ciclo, (B) captura
de negativos reales, (C) reentrenar con el nombre nuevo, (D) ajustar umbral/patience con datos.

### A. Capas baratas en runtime (sin reentrenar)

1. **Verificador de segundo paso con Whisper (el STT ya cargado).** Al disparar el wake, antes de abrir
   `cycle()`, coger `MIC.recent(2.5)` (hay que subir `maxlen` de `_recent` de 1,5 s a ~3 s) y transcribir
   con `faster-whisper small` en CUDA, `language="es"`, `initial_prompt="Perséfone, Laura, oye..."`,
   `without_timestamps`. Abrir la escucha solo si el texto normalizado contiene el nombre (fuzzy:
   `rapidfuzz.partial_ratio >= 80` contra el nombre y sus variantes, p. ej. «laura despierta» o
   «perséfone»). Con la frase actual exigiría «despierta» y mataría la mayoría de los falsos.
   - **Coste**: solo se ejecuta en cada disparo (≈4/h en el peor caso medido): ~0,15-0,3 s de GPU
     (`small` en RTX 4050 con 2,5 s de audio), 0 en reposo, sin VRAM extra (modelo ya cargado). En modo
     juego el wake ya está pausado. Añade ~200-300 ms de latencia al disparar; aceptable.
   - Alternativa sin Whisper: usar solo el VAD (silero-vad ya está en el venv, lo usa el barge-in) para
     descartar disparos cuando no hay voz humana real en los últimos 1,5 s. Coste ~1 ms por bloque de
     32 ms en CPU. Útil contra ruido/música, no contra habla.
2. **VAD previo al wake**: no pasar al modelo ventanas sin voz (ya hay silero cargado). Ahorra CPU
   (el wake corre 12,5 inferencias/s siempre) y evita picos por ruido. Coste: ~0,5 % de un núcleo.
3. **Reducir el daño de un falso**: los ciclos abiertos por wake empiezan en **un solo turno** (como
   `barra`) hasta que el nombre esté verificado; o exigir que el primer turno tenga `>= 2` palabras y
   `no_speech_prob`/`avg_logprob` razonables antes de pasarlo al LLM. Los «tú:» de charla ambiente no
   deben llegar al LLM ni a las herramientas.
4. **Log de depuración de cada disparo** (`score`, `racha`, y guardar 3 s de audio en
   `~/.local/share/laura/wake/capturas/ts.wav`). Es lo que alimenta los negativos reales (paso B).
5. **Eco**: si hay tele/Spotify sonando (ya se sabe por las herramientas), subir el umbral de ese
   momento o pausar el wake; con AEC (PipeWire `module-echo-cancel`) en la fuente del micro se corta
   gran parte del problema. Coste: ~2-4 % de un núcleo.

### B. Datos: más negativos y de verdad

Todo en `~/.local/share/laura/wake/` (ya está ahí el material de la tanda anterior).

1. **Habla de Alberto en español, horas, no 90 s.** Mientras trabaja, grabar el micro continuamente
   durante 2-3 días (`pw-record --target <micro> -r 16000 -c 1 --format s16 ...` por trozos de 10 min)
   y trocearlo. Es el dato más importante; ver también `interacciones.jsonl` para saber qué dice.
2. **TV y música**: grabar el *monitor* del sistema (lo que sale por altavoces/tele) y la sala con
   Spotify/YouTube/series en español, 30-60 min cada uno, con y sin habla de fondo.
3. **Corpus público de habla española** como negativos masivos (CC0/abierto): Common Voice es,
   VoxPopuli es o MLS Spanish, unas 20-50 h; basta con sacar `AudioFeatures` de ellos.
4. **Negativos duros del propio modelo** (hard-negative mining): pasar el modelo viejo sobre todo lo de
   arriba, guardar todos los clips con score `>=0,3` y añadirlos con peso alto. Repetir 2 iteraciones.
5. **Positivos nuevos con voz real**: 60-80 tomas de Alberto con el nombre nuevo (`grabar.py`),
   a distintas distancias/volumen, con y sin TV de fondo, y más sintéticos TTS (Piper + Kokoro).

### C. Entrenar el modelo nuevo con lo que ya hay en `wake_train/`

Hay que parametrizar los scripts (hoy llevan «Laura/despierta» y «Aurora» fijos):

1. `sinteticos.py`: sustituir `POS_TXT` por «Perséfone», «Oye, Perséfone», «Perséfone, ¿estás ahí?»,
   etc., y `CASI`/`CONFUSABLES` por parecidos del nombre nuevo («persuasión», «Seferina», «Sofía», «perfecto»,
   «percepción», «Prosérpina», «Fernando»...). Sacar el nombre de una constante `NAME`.
2. `grabar.py`: mismo cambio en los textos que muestra; añadir un modo `--solo tv` para mezclar habla con
   TV. 
3. `entrenar.py`: aceptar `--nombre`, `--oww` y un directorio `neg_real/` (los datos de B1-B4).
   Si el nombre es una sola palabra, el truco del «cortado» hay que tomarlo por sílabas
   (recortar al 40-70 % del clip como negativo) en vez de «antes de despierta».
   Mantener el peso de negativos creciente pero medir el **falso/h contra Spanish held-out** (parte
   de B1-B3 que no se entrena), no solo contra el set inglés de openWakeWord.
4. Comandos (en `assistant/`):
   ```
   .venv/bin/python wake_train/sinteticos.py --pos 2000 --neg 4000   # con NAME nuevo
   .venv/bin/python wake_train/grabar.py --tomas 60                    # tu voz con el nombre nuevo
   .venv/bin/python wake_train/grabar.py --solo neg                    # y/o importar la grabación larga
   .venv/bin/python wake_train/entrenar.py --epocas 60 --rehacer       # recalcula la caché
   .venv/bin/python wake_train/probar.py --modelo models/persefone.onnx --umbral 0.8 --patience 3
   ```
   Guardar como `models/persefone.onnx` y no pisar `laura.onnx` hasta validarlo.
5. **Criterio de aceptación**: detección `>=95 %` en tomas no vistas de Alberto **y** `<= 0,5 falsos/h`
   medidos sobre 5 h de habla española y TV held-out (no solo ruido en inglés). Si no, más negativos
   (B4) antes de tocar el umbral.
6. Commitear `wake_train/` y el modelo (hoy están sin versionar), o al menos un `.gitignore`
   explícito para los datos.

### D. Umbral y patience

- Con modelo nuevo y verificador: dejar `threshold = 0.7-0.8` (más sensibilidad: el verificador filtra
  falsos) y `patience = 3`.
- Sin verificador: no tocar (ya está justo); el cambio útil es **ventanas de 80 ms x patience 4 solo
  cuando hay audio de fondo** (TV).
- Medirlo con `probar.py` sobre las grabaciones largas, no «a ojo».
- `cooldown = 3.0` está bien; subirlo a 6-8 tras un falso positivo detectado (no hay ciclo) evita
  ráfagas.

### Resumen de costes

| Capa | CPU | GPU/VRAM | Latencia añadida |
|---|---|---|---|
| Wake actual (openWakeWord) | ~2-4 % de 1 núcleo, siempre | 0 | 0 |
| VAD previo (silero) | +~0,5 % de 1 núcleo | 0 | ~0 |
| Verificación Whisper | 0 en reposo | ~0,2 s GPU por disparo (modelo ya cargado) | ~200-300 ms |
| AEC PipeWire | 2-4 % de 1 núcleo | 0 | ~0 |
| Reentrenar | 1-2 h CPU + embeddings | opcional (CUDA para el MLP) | solo una vez |

## 6. Mitigación inmediata sin reentrenar (esta misma tarde)

Por orden, de menos a más cambio:

1. **Subir `cooldown` y reducir el daño**: `cooldown = 8`, y que un ciclo abierto por wake sea de
   **un turno** hasta verificar. Reduce de 4 a ~1 el número de respuestas al aire por falso.
2. **Verificador con Whisper** (A1): son ~30-40 líneas en `wake.py`/`daemon.py`, usa el STT cargado y
   solo corre al disparar. Es la medida con más efecto: la frase real «Laura despierta» debe contener
   «despierta», y casi ningún falso lo contiene. Es la propuesta recomendada para hoy.
3. **Si no se toca código**: `[wake] enabled = false` y usar solo el atajo `SUPER+A` hasta tener el
   modelo nuevo. Los números de arriba (≈85-90 % falsos, ~3,8/h con la tele/charla) justifican apagarlo
   si molesta antes de poder reentrenar.
4. No subir `threshold` a 0,9/0,95: ya se probó, no ayuda (mediana de falsos 0,955) y le quita
   sensibilidad al positivo real.
5. En paralelo, empezar ya la **captura de audio de los disparos** (A4) para que el reentrenamiento
   con el nombre nuevo tenga datos reales desde el primer día.

## 7. Pasos propuestos

1. Elegir nombre (recomendado: **Perséfone**; alternativa **Calíope**).
2. Hoy: verificador Whisper + ciclo de 1 turno + captura de disparos (código en `assistant/laura/`).
3. Esta semana: grabar 2-3 días de habla/TV, parametrizar `wake_train/`, entrenar
   `models/<nombre>.onnx`, medir contra español held-out y activar.
4. Renombrar en `config.toml` (`system_prompt` «Eres Laura», frase de wake, `stop_phrases` «con o sin
   Laura»), README, `docs/LAURA-HOLO.md` y la evaluación de `eval/`.
