# Laura v2 — plan

Rama `feat/laura-v2` (worktree `.worktrees/laura-v2`, sale de `main` y se mergea a `main`).
Decidido con Alberto el 2026-10-20.

## Decisiones

- **Se mantiene `laurad`** (no se migra a Hermes Agent ni a isair/jarvis). Hermes está pensado
  para modelos grandes (contexto ≥64K, GPU de 8 GB o más) y su voz no conoce Quickshell/Hypr.
  Se copian sus ideas: memoria persistente, tareas programadas, frases de corte, escalada asíncrona.
- **Voz propia y 100 % local.** Hoy `tts.engine = "edge"` es la nube de Microsoft. VoiceStudio
  (debpalash/VoiceStudio, AGPL, Electron) se usa como **laboratorio** para diseñar o clonar la voz;
  Laura llama directamente a un motor ligero (candidatos: OmniVoice, PocketTTS, Supertonic 3).
  Medir latencia del primer audio y calidad en español antes de elegir.
- **Modelos a examinar** (caben en la RTX 4050 de 6 GB): `qwen3.5:4b`, `gemma4:e4b`,
  `qwen3.5:9b` (modo calidad) frente al actual `qwen3:4b-instruct`. Qwen3.8 solo existe en 27B.
- **Ajuste fino (fase 4):** LoRA con Soup (MakazhanAlpamys/Soup, layer streaming en GPUs de 4 GB)
  sobre el modelo ganador del examen; datos sintéticos generados a partir de `tools.TOOLS` + logs reales.

## Fases

1. **Base** — partir `laurad.py` en el paquete `laura/`, modo `--text`, examen `assistant/eval/`.
2. **Herramientas** — memoria persistente, temporizadores/recordatorios, hora y tiempo,
   búsqueda web real, luces Magic Home / teclado / pantallas (helpers de `widgets/` y `rgb/`),
   brillo, batería, wifi/bluetooth, y `escalar_a_claude` asíncrono con confirmación por voz
   (junto al modo B de `agy`, que deja de bloquear).
3. **Voz** — motor TTS local con la voz de Laura, interrumpirla hablando (barge-in), wake word.
4. **Ajuste fino** — Soup, comparado contra el examen.

## Lo que hace Alberto (instalaciones)

- `ollama pull qwen3.5:4b && ollama pull gemma4:e4b && ollama pull qwen3.5:9b`
- Skills de Matt Pocock: `npx skills@latest add mattpocock/skills` → marcar `handoff`, `grill-me`,
  `improve-codebase-architecture`, `prototype`, `git-guardrails-claude-code`, `research`.
- VoiceStudio: `curl -fsSL https://voicestudio.sh/install | sh`, diseñar la voz de Laura y exportar
  una muestra limpia de referencia (10–20 s + su transcripción).
