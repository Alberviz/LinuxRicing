# Laura y Google Workspace: conexión directa

`correo`, `agenda`, `crear_evento` y el vigía hablan **directamente** con un servidor MCP local
([`workspace-mcp`](https://github.com/taylorwilsdon/google_workspace_mcp)), sin LLM por medio. Aurora
queda para enviar correo, para lo pesado (Drive, Docs, recados) y como **respaldo automático** si el
servidor no responde o no está autenticado.

## Permisos

El servicio arranca con `--permissions gmail:readonly calendar:full` (excluyente con `--tools` y
`--read-only`). Niveles de Gmail: `readonly`, `organize`, `drafts`, `send`, `full`; del resto,
`readonly` o `full`. Laura **no puede enviar ni borrar correo**: escribir lo hace Gemini (solo texto)
y el envío, tras tu confirmación, Aurora. Crear eventos siempre pide confirmación.

Herramientas MCP reales con esos permisos: `search_gmail_messages`, `get_gmail_message_content`,
`get_gmail_messages_content_batch`, `get_gmail_thread_content`, `list_gmail_labels`, `get_events`,
`manage_event` (action `create`), `list_calendars`, `query_freebusy`, `start_google_auth`, etc. El
cliente (`assistant/laura/workspace.py`) las descubre con `tools/list`.

## Pasos

1. **Credenciales.** `~/.config/laura/workspace.env` (chmod 600) con `GOOGLE_CLIENT_SECRET_PATH`
   (ruta al JSON del cliente OAuth de escritorio) o `GOOGLE_OAUTH_CLIENT_ID` y
   `GOOGLE_OAUTH_CLIENT_SECRET`, más `WORKSPACE_MCP_PORT=8765` y `OAUTHLIB_INSECURE_TRANSPORT=1`.
2. **Servicio.**
   ```bash
   cp assistant/laura-workspace.service ~/.config/systemd/user/
   systemctl --user daemon-reload && systemctl --user enable --now laura-workspace
   ```
3. **Primer login OAuth.** La primera llamada sin credenciales devuelve «ACTION REQUIRED: Google
   Authentication Needed» con una URL: ábrela en el navegador y autoriza. Laura lo detecta, cae a
   Aurora y deja un aviso de prioridad baja con la URL (una vez al día).
4. **Cuenta.** Pon tu correo en `[workspace] email` de `assistant/config.toml` (las herramientas
   exigen `user_google_email`).
5. **Comprobar.**
   ```bash
   systemctl --user status laura-workspace
   cd assistant && .venv/bin/python laurad.py --text "mírame los correos"
   .venv/bin/python laurad.py --text "qué tengo mañana"
   python3 tests/mock_workspace.py          # pruebas con servidor simulado (sin red)
   ```

## Qué hace cada cosa

- **Correo**: filtro «sin spam» = `in:inbox (category:primary OR category:updates)
  -category:promotions -category:social -category:forums -in:spam`, combinado con lo que pidas.
- **`correo` / `agenda`**: síncronas; devuelven una lista compacta y un campo `decir` ya redactado.
- **`crear_evento`**: trabajo en `confirm` con el evento exacto en la tarjeta; solo se crea al decir sí.
- **`redactar_correo`**: Gemini (agy, solo lectura, sin herramientas) escribe `{para, asunto, cuerpo}`;
  pasa a `confirm` («Te lo he escrito, ¿lo envío?»); al confirmar, Aurora recibe «Alberto YA lo ha
  confirmado: envía EXACTAMENTE este correo…». Si cancelas, no se envía nada.
- **Vigía** (`[vigia]`, cada 5 min por defecto): no leídos de las últimas 24 h con el filtro anterior
  y eventos que empiezan dentro de `aviso_evento_min`. Prioridad: principal `normal`, Notificaciones
  `baja`; `alta` con palabras de urgencia (plazo, entrega, pago, factura, examen, urgente, vuelo, hoy,
  mañana) o remitente en `remitentes_importantes`. Los avisos hablados usan `mode="aviso"` en el evento
  de estado.
