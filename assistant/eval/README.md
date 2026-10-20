# Examen de modelos para Laura

Banco de frases (`frases.toml`) para comparar modelos de Ollama: acierto de herramientas,
argumentos, falsos positivos y latencia. No ejecuta las herramientas, solo mira qué pide el modelo.

```bash
cd assistant
/home/alberviz/LinuxRicing/assistant/.venv/bin/python eval/run.py --model qwen3:4b-instruct --model qwen2.5:7b-instruct
# opciones: --repeat N (repite cada frase), --limit N (solo las N primeras)
```

Usa el system prompt, `num_ctx` y `TOOLS` actuales. Antes de medir para el servicio `laura` (libera GPU) y lo arranca al acabar (`--no-daemon` lo evita; si hay un daemon del worktree activo espera y reintenta). Límite de 30 s por frase (timeout = fallo) y más de 4 tool_calls = cascada. «sin tool» = respondió hablando cuando se esperaba herramienta (dice que actuó sin actuar). Resultados por modelo en `results/`. Ojo: otros usos de GPU alteran las latencias.
fallos en `results/<fecha>-<modelo>.md`. Cierra Laura/otros usos de GPU antes: afectan a las latencias.

## Añadir frases

Añade un bloque a `frases.toml`:

```toml
[[frase]]
texto = "baja el volumen un veinte"
espera = ["volumen"]          # [] = no debe usar herramienta
args = [{porcentaje = -20}]   # opcional, uno por herramienta; texto = subcadena sin tildes, números exactos
grupo = "trampa"              # opcional (informativo)
```
