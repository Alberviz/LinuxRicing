---
fileClass: Backlog
tipo: tarea
estado: hecha
prioridad: 2
area: agentes
origen: Alberto
esfuerzo: M
creado: 2026-09-05
flujo: "[[Asistente de voz con IA local]]"
tags:
  - backlog
---

# Laura puede abrir sesiones de Gemini para todo lo que no sabe hacer

Implementado en la rama `feat/laura-gemini-escalation` (a integrar en `main`).
Todo lo que Laura no pueda resolver ella misma se lo pide a Gemini (Antigravity,
CLI `agy`) y devuelve la respuesta como si fuera suya. Dos modos, configurables
en `assistant/config.toml` bajo `[escalation]`:

## Modo A — automático, sin confirmar

Casos rutinarios pre-programados (`[escalation].auto_cases`): si el texto que
dice Alberto contiene alguna de las `keywords` de un caso (p. ej. «busca en
internet», «qué es», «qué tiempo hace», «dato rápido»…), Laura **ni siquiera se
lo pregunta al LLM local** — intercepta el texto justo tras transcribirlo (en
`cycle()`, antes del cambio de modo y antes de `converse()`), lo manda tal cual
a un Gemini **ligero** (`model_auto` / `effort_auto`, por defecto
`gemini-3.8-flash-low` / `low` — el más ligero disponible en `agy models`) y
lee la respuesta en voz alta. Pensado para búsquedas web / datos rápidos que el
modelo local no puede saber porque no tiene acceso a Internet.

La lista de casos es una tabla TOML abierta — se añaden más sin tocar código:

```toml
auto_cases = [
  { nombre = "mi_caso", keywords = ["frase que dispara esto", "otra variante"] },
]
```

## Modo B — con confirmación

El LLM local, con tool-calling, decide llamar a la herramienta nueva
`escalar_a_gemini(peticion, motivo)` (definida en `assistant/tools.py`) cuando
la petición es compleja, implica modificar código/configuración del ecosistema,
o está claramente fuera de sus otras herramientas (ejemplo del propio Alberto:
«haz que el reloj marque la hora en formato 12 horas»). El system prompt le
dice explícitamente que use esta tool en vez de improvisar una respuesta.

`converse()` detecta esa llamada especial y **no sigue el bucle normal de
tools**: devuelve una `escalada` pendiente en vez de una respuesta. `cycle()`
entonces:

1. Laura pregunta por voz: *"Esto se me escapa. ¿Quieres que se lo mande a
   Gemini para que lo resuelva?"*
2. Escucha la respuesta (turno de voz corto, mismo mecanismo que el
   follow-up de modo centro).
3. Si es que no → *"Vale, no hago nada."* y sigue la conversación normal.
4. Si es que sí → construye un prompt bien formado con `_build_gemini_prompt()`
   (plantilla fija con contexto del repo: ruta, convención de ramas de
   `CLAUDE.md`, qué no debe tocar el agente) + la petición de Alberto, y lanza
   `agy` con el modelo fuerte (`model_confirm` / `effort_confirm`, por defecto
   `gemini-3.1-pro-high` / `medium`, con `--add-dir ~/LinuxRicing`).
5. Al volver, pide al LLM local que **resuma en 1-2 frases orales** la
   respuesta completa de Gemini (`_summarize_for_voice()`, con fallback a un
   recorte crudo si el resumen falla) y se lo lee a Alberto integrado como si
   lo hubiera hecho ella misma.

## Mecánica común

- `_run_agy()` en `assistant/laurad.py` lanza `agy -p <prompt> --model <m>
  --effort <e> --dangerously-skip-permissions [--add-dir <dir>]` con
  `subprocess.Popen`, poll no bloqueante con `cancel` (se puede abortar con el
  atajo) y `timeout` configurable; nunca lanza excepción, siempre devuelve
  `{"ok": bool, "texto"|"error": str}`.
- Ambos modos registran la petición y la respuesta en el historial de
  conversación (`_messages`) para que el hilo de la charla no se rompa.
- Fallos (binario `agy` no encontrado, timeout, exit code ≠ 0, cancelado) se
  traducen a una frase hablada de error, nunca a una excepción que tumbe el
  daemon.

## Cómo probarlo (Alberto)

1. **Round-trip de `agy` solo** (antes de nada, para confirmar que el binario
   funciona con el modelo ligero elegido):
   ```fish
   agy -p "say hello" --model gemini-3.8-flash-low --effort low --dangerously-skip-permissions
   ```
   *Nota de la sesión de implementación (2026-09-05): en el momento de probar,
   la cuota individual de Antigravity estaba agotada («Individual quota
   reached… resets in ~13m»), tanto en `gemini-3.8-flash-low` como en
   `gemini-3.7-flash-low` — parece ser cuota de cuenta, no de modelo concreto.
   No se pudo confirmar el round-trip real end-to-end en esta sesión; revisar
   con cuota disponible.*
2. **Modo A:** reiniciar `laura.service`, activar con el atajo, decir algo como
   «qué tiempo hace en Madrid» — debería ir directo a Gemini sin pasar por
   Qwen local (mirar el log: `Modo A (busqueda_web) -> Gemini ligero`).
3. **Modo B:** decir algo claramente fuera de las tools existentes, p. ej. «haz
   que el reloj marque la hora en formato 12 horas» — Laura debería preguntar
   si mandarlo a Gemini; responder que sí y comprobar que `agy` se lanza con
   `--add-dir ~/LinuxRicing` y que al terminar Laura resume el resultado.

## Pendiente / lo que Alberto puede querer ajustar

- Los `auto_cases` de ejemplo (`busqueda_web`, `dato_rapido`) son un punto de
  partida por keywords — si en uso real hay falsos positivos/negativos,
  ajustar la lista en `config.toml` (no requiere tocar código).
- No se ha verificado el round-trip real de `agy` en esta sesión por cuota
  agotada (ver nota arriba) — Alberto debe confirmarlo antes de dar esto por
  cerrado del todo.
- El resumen de la respuesta de Gemini para Modo B pasa por una llamada extra
  al LLM local (`_summarize_for_voice`); si resulta lento o innecesario en la
  práctica, se puede simplificar a un recorte crudo del texto de Gemini.
