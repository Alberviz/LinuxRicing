# Del adaptador al modelo de Ollama `laura-qwen3:4b`

Tras `soup train` hay un adaptador LoRA en `finetune/output/`. Pasos (desde `assistant/finetune/`):

1. **Fusionar y exportar a GGUF** (Soup invoca llama.cpp; necesita una copia compilada,
   ver la sección «Serving & export» de su documentación):

   ```bash
   soup merge  --adapter ./output                                   # LoRA -> modelo completo
   soup export --model ./output --format gguf --quant q4_k_m        # -> ./output/model.q4_k_m.gguf
   ```

   Si `soup export` no encuentra llama.cpp: `--llama-cpp /ruta/a/llama.cpp`.
   Para más calidad usa `--quant q5_k_m` o `q8_0` (cabe de sobra en 6 GB con un 4B).

2. **Modelfile.** Debe reproducir la plantilla de chat con tools de `qwen3:4b-instruct`, o el
   modelo no verá las herramientas. Lo más seguro es partir de la plantilla original:

   ```bash
   ollama show qwen3:4b-instruct --modelfile > Modelfile.orig
   ```

   Crea `Modelfile` copiando de `Modelfile.orig` las líneas `TEMPLATE`, `PARAMETER` (stop,
   temperature…) y cambiando SOLO la primera línea:

   ```
   FROM ./output/model.q4_k_m.gguf
   # …TEMPLATE """…""" y PARAMETER copiados de Modelfile.orig…
   PARAMETER num_ctx 6144
   ```

3. **Crear y probar:**

   ```bash
   ollama create laura-qwen3:4b -f Modelfile
   ollama run laura-qwen3:4b "pon el volumen al diez"     # debe emitir una llamada a `volumen`
   ```

   Atajo equivalente de Soup (sin plantilla personalizada, solo si la plantilla por defecto
   que genera sirve): `soup deploy ollama --model ./output/model.q4_k_m.gguf --name laura-qwen3:4b`.
   Comprueba con `ollama show laura-qwen3:4b --modelfile` que la `TEMPLATE` incluye `.Tools`;
   si no, usa el Modelfile manual.

4. **Examen** (ver README.md): `eval/run.py --model laura-qwen3:4b`. No cambies
   `[llm] model` de `config.toml` hasta que supere el criterio de adopción.
