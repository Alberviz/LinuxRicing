# Runbook — Captura USB en Windows (ingeniería inversa de hardware Akko/MCHOSE)

> Para el **agente de Windows**. Si empiezas una conversación nueva y el objetivo es
> capturar tráfico USB de un periférico, **lee esto entero antes de tocar nada**. Todo
> lo de aquí ya se ha probado — no lo re-investigues.
> Última actualización: 2026-08-28.

---

## 1. Entorno (verificado)

| Cosa | Dónde | Notas |
|---|---|---|
| Windows | build **26200** (11, muy nueva) | relevante para el bug de USBPcap, §4 |
| Wireshark | `C:\Program Files\Wireshark\` (4.6.8) | `tshark.exe`, `dumpcap.exe`, `editcap.exe`, `capinfos.exe` |
| USBPcap | `C:\Program Files\USBPcap\USBPcapCMD.exe` (1.5.4.0) | instaladores en `~/Downloads/USBPcapSetup-1.5.4.0*.exe` |
| **Wireshark NO tiene el extcap de USBPcap** | `extcap\` solo tiene `etwdump.exe` | ⇒ `dumpcap -D` **no** lista interfaces USB. Hay que usar `USBPcapCMD.exe` a pelo. |
| Python | 3.11, con `openrgb`, `pillow`, `hid` | |
| Akko Cloud Driver | `%LOCALAPPDATA%\Programs\Akko Cloud Driver\Akko Cloud Driver.exe` | arranca `iot_driver_v200.exe` = **bridge gRPC en `127.0.0.1:3814`** |
| iot_driver desempaquetado | `%APPDATA%\Akko Cloud Driver\iot_driver_v200.exe` | se puede arrancar suelto |

USBPcapCMD necesita **elevación**. Lanzar con:
`Start-Process powershell -Verb RunAs -Wait -ArgumentList "-File","<script>.ps1"`
(el usuario acepta el UAC). Puede cancelarlo sin querer — reintenta.

---

## 2. El dongle Akko 2.4 GHz

- USB `3151:4011` (dongle 2.4 GHz). Teclado por cable = `3151:4015`.
- Interfaz de control = **MI_02 / interfaz 2**. Feature reports.
- **El sufijo del instance path de Windows (`8&xxxxxxxx`) CAMBIA entre máquinas y
  reinicios. NUNCA hardcodear.** Resolver siempre en caliente:
  ```python
  import hid
  next(d['path'].decode() for d in hid.enumerate(0x3151,0x4011) if 'mi_02' in (d['path'].decode() if isinstance(d['path'],bytes) else d['path']).lower())
  ```
- En el bus: root hub `USB\ROOT_HUB30\4&1c1e67e3` vía hub ASMedia `174C:2074`.
  Históricamente **USBPcap device address 6**, control device **`\\.\USBPcap3`**.
  Todo esto puede cambiar entre sesiones — **verificar cada vez** (§5 paso 3).

---

## 3. Captura USB — el comando que funciona (cuando USBPcap va)

```powershell
# elevado:
& "C:\Program Files\USBPcap\USBPcapCMD.exe" -d \\.\USBPcap3 -o out.pcap -A --inject-descriptors
# parar:  Get-Process USBPcapCMD | Stop-Process -Force
```
```bash
# filtrar al dongle y pasar a pcapng:
tshark -r out.pcap -Y "usb.device_address==6" -w filtered.pcapng -F pcapng
# decodificar payloads de control OUT:
tshark -r filtered.pcapng -Y "usb.device_address==6 && usb.bmRequestType==0x21 && usb.data_len>0" -x
```
El campo `usb.capdata` sale vacío en tshark para estos SET_REPORT; usar `-x` y parsear
los bloques `USB Control (NN bytes):` (los 7 primeros bytes son cola del setup, el resto
es el payload del report).

---

## 4. ⚠️ El fallo de USBPcap en esta build de Windows (intermitente)

**Novedad 2026-08-28:** tras un apagado completo (no reinicio) y arranque limpio,
`USBPcapCMD -d \\.\USBPcap3 -o f -A --inject-descriptors` **volvió a funcionar** a la
primera y capturó sin problema el color sólido *y* el per-key (opcode `0x0C`). O sea:
el fallo de abajo es **intermitente y ligado al estado del driver en memoria**, no una
incompatibilidad permanente. Si falla: **apagado completo** (Shutdown, no Restart) y
capturar como primera acción. `\\.\USBPcap3` = hub del dongle; device address cambió a
**7** esa sesión (verificar siempre, no asumir 6).

**Síntoma (cuando está roto):** `USBPcapCMD -d \\.\USBPcapN -o f -A` (o `--devices N`) falla con
**`Couldn't open device - 2`** y deja el fichero a **0 bytes**. Solo abrir el control
device sin `-A` ni `--devices` funciona, pero no captura nada
(`Selected capture options result in empty capture`).

- `USBPcapCMD --extcap-interfaces` puede **listar** `\\.\USBPcap1/2/3` aunque la captura
  esté rota. **Listar ≠ capturar.**
- **Funcionó** a principios de la sesión del 2026-08-27 (rawB 4.9 MB, rawF 9 MB) y
  **dejó de funcionar tras el primer reinicio.** Estado en memoria del driver = frágil.
- **NO lo arreglan:** 3 reinicios · uninstall+reinstall limpio de 1.5.4.0 ·
  `USBPcapCMD -I` (los hubs son "standard HWID", no hace nada) ·
  `pnputil /restart-device` sobre los root hubs (el hub del dongle dice "reinicio
  necesario para completar" y tras reiniciar sigue fallando).
- **Causa probable:** USBPcap 1.5.4.0 (última release, 2020, proyecto muerto) es
  incompatible con el manejo de device objects xHCI de Windows 11 build 26200. El
  camino `-A`/`--devices` enumera y abre cada device hijo del hub, y ese open falla.

**Si USBPcap está en este estado, NO pierdas horas.** Opciones, por orden:
1. Un reinicio limpio y capturar **inmediatamente como primera acción**, antes de que
   nada más toque el USB. (~40 % de éxito, sin garantías.)
2. Otra herramienta de captura (no hay USBPcap más nuevo; valorar un analizador HW).
3. Analizar `iot_driver_v200.exe` estáticamente en vez de capturar.
4. Hacerlo en una máquina con Windows más antiguo.

---

## 5. Qué está RESUELTO y qué no

### ✅ Resuelto — NO re-investigar (ver `docs/AKKO_2.4G_USB_FINDINGS.md`)

- **Color sólido por 2.4 GHz funciona.** Protocolo = protocolo del modo cable:
  `07|08 01 04 04 08 RR GG BB CK` + ceros (64 bytes), Feature report (`SET_REPORT`,
  `wValue=0x0300`, `wIndex=0x0002`), interfaz 2.
  `CK = (0xFF - (sum(byte[0..7]) & 0xFF)) & 0xFF` en byte[8].
  `0x07` = backlight, `0x08` = tira lateral, misma estructura.
- **No hacen falta** `setLightType`, `changeWirelessLoopStatus`, ni "flush `0x88`".
- `rgb/sync-rgb-windows.py` arreglado: ruta dinámica (`resolve_akko_dongle_path()`),
  parafernalia gRPC quitada. **Necesita `iot_driver_v200.exe` corriendo.**
- Capturas de referencia en `docs/pcap/`.

- **LEDs per-key / per-zona** — ✅ **capturado el 2026-08-28** (`docs/pcap/akko-2.4g-perkey.pcapng`).
  Opcode `0x0C`: `07 0d` (modo custom) + 7 frames `0c 00 80 01 <idx> 00 00 <ck>` con
  un array plano de 128 LED × RGB troceado en chunks de 56 bytes. Detalle completo en
  `docs/AKKO_2.4G_USB_FINDINGS.md` §"Per-key". Falta portarlo a Linux y verificar.

### ❌ No resuelto

- Confirmar en Linux que los paquetes Feature a `:1.2` (color sólido `0x07/0x08` y
  per-key `0x0C`) cambian las luces por 2.4 GHz.

### Receta para re-capturar el per-key (si hace falta más detalle)

1. Arrancar "Akko Cloud Driver" (`%LOCALAPPDATA%\Programs\Akko Cloud Driver\...`),
   esperar a que el puerto 3814 responda.
2. Resolver el path MI_02 del dongle (§2) y su `usb.device_address` actual.
3. **Self-test primero:** capturar ~5 s con `-A --inject-descriptors` en `\\.\USBPcap3`,
   disparar `sync_akko_keyboard((0,180,255))`, parar. Si el `.pcap` > 24 bytes y contiene
   el `07 01 04 04 08 00 b4 ff` → OK. Si 24 bytes → USBPcap roto, §4 (apagado completo).
4. Captura de ~150 s. El usuario pinta en Akko Cloud Driver, modo **DIY/custom**, un
   patrón distinguible y da a aplicar.
5. Parar, `tshark -r raw.pcap -Y "usb.device_address==N" -w f.pcapng`. Parser de
   payloads: los bloques `USB Control (NN bytes):` empiezan por `Packet (` (no `Frame (`),
   y los 7 primeros bytes (`09 00 03 02 0X 40 00`) son cola del setup.

---

## 6. Coordinación

- Las peticiones de los agentes de Linux llegan a
  `vault/Rice LinuxRicing/00 - Arquitectura/Tareas de Agentes/`. Responder ahí mismo.
- Al terminar, `git add` + `commit` + `push` (hotfix directo a la rama activa según
  `CLAUDE.md`). `git fetch` a menudo.
