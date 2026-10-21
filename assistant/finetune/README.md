# Ajuste fino de Laura (LoRA con Soup)

Objetivo: que un 4B local llame a las herramientas de Laura con más fiabilidad (hoy
`qwen3:4b-instruct` saca ~91 % en el examen y suele fallar en frases coloquiales, dobles
acciones y en escalar en vez de decir «no puedo»). No toca el modelo por defecto: es un
experimento que Alberto adopta o descarta según el examen.

Herramienta: [Soup](https://github.com/MakazhanAlpamys/Soup) (`pip install "soup-cli[train]"`,
Python 3.11–3.13). Formato de datos y campos de `soup.yaml` tomados de su documentación
(`format: tool-calling`) y de su `config/schema.py`.

## Qué hay aquí

| Fichero | Para qué |
|---|---|
| `gen_dataset.py` | Genera `data/train.jsonl` (+ `heldout.json`, `stats.json`). |
| `check_dataset.py` | Valida el JSONL: herramientas y argumentos reales, sin fuga de held-out. |
| `soup.yaml` | QLoRA sobre `Qwen/Qwen3-4B-Instruct-2507`, NF4 + `stream_layers` para 6 GB. |
| `export.md` | GGUF y modelo de Ollama `laura-qwen3:4b`. |

## El dataset

~2600 ejemplos (`--target` cambia el tamaño). Cada fila trae el system prompt REAL de
`config.toml` y los esquemas REALES de `laura.tools` (campo `tools`), con trayectorias
completas: usuario → `tool_calls` → resultado simulado → frase final corta en español.
Orígenes (ver `data/stats.json`): frases del examen con variaciones (~840), plantillas por
herramienta con huecos (~1070), escaladas a Gemini/Claude en vez de «no puedo» (~180), dobles
acciones (~190) y negativos sin herramienta (~320: charla y trampas que mencionan wifi,
volumen… sin ser una orden). Variaciones: muletillas, sufijos, minúsculas y errores típicos de
Whisper (sin tildes, b/v, h muda, palabras comidas, k por qu).

**Contaminación.** El 20 % de `eval/frases.toml` (22 de 139, estratificado por herramienta
esperada, semilla fija) se aparta en `data/heldout.json` y **nunca** entra en el entrenamiento:
tampoco cualquier frase generada con Jaccard de palabras ≥ 0.7 respecto a ellas. El examen
completo (139 frases) sigue valiendo, pero la cifra honesta de generalización es la de las 22
held-out; el resto son frases con las que se ha entrenado variaciones. Si cambias la semilla o
`frases.toml`, regenera y vuelve a comprobar.

Regenerar y comprobar (no necesita GPU ni Soup):

```bash
cd ~/LinuxRicing/assistant
.venv/bin/python finetune/gen_dataset.py
.venv/bin/python finetune/check_dataset.py
```

`data/` y `output/` están en `.gitignore` (45 MB de JSONL; el generador sí está versionado).

## Lo que ejecuta Alberto

```bash
# 1. Entorno aparte (no mezclar con el venv de Laura: trae torch/peft/trl)
python3.12 -m venv ~/soup-venv && source ~/soup-venv/bin/activate
pip install "soup-cli[train]"

# 2. Comprobar la config y el hardware
cd ~/LinuxRicing/assistant/finetune
soup doctor --config soup.yaml

# 3. Parar lo que ocupe la GPU y entrenar (Ollama, Laura, etc. liberan VRAM)
systemctl --user stop laura; ollama stop qwen3:4b-instruct
soup train --config soup.yaml

# 4. Exportar a Ollama: seguir export.md  (soup merge, soup export --format gguf, ollama create laura-qwen3:4b)

# 5. Examen (el script para y arranca el servicio laura solo)
cd ~/LinuxRicing/assistant
.venv/bin/python eval/run.py --model laura-qwen3:4b
```

El entrenamiento con `stream_layers` es lento (horas) y es una función BETA de Soup; si falla
por VRAM, reduce `lora.r` o `gradient_accumulation_steps`; los esquemas de las 42 tools ocupan
unos 4,3k tokens por ejemplo, así que `data.max_length` no se puede bajar mucho.

## Criterio de adopción

Cambiar `[llm] model` en `config.toml` a `laura-qwen3:4b` solo si, en el examen completo:

1. herramientas **> 91 %** (la base actual), y **> 91 % también sobre las 22 frases
   held-out** (`data/heldout.json`; compara a mano las que falle);
2. **0 falsos positivos** (grupo `trampa`; hoy 0/18) y sin cascadas ni timeouts;
3. latencia similar (ttft medio ~0,5 s) y respuestas cortas.

Si no, se descarta o se reentrena (más ejemplos de los grupos que fallen, menos épocas).
