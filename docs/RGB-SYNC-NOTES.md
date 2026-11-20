# Notas: sincronización RGB con el tema de Caelestia

Registro de todo lo tocado en esta sesión sobre el setup de RGB (OpenRGB +
`sync-rgb.py` + parche de vista previa del wallpaper). Pensado para que,
dentro de unos meses, tú o cualquiera pueda entender qué se hizo, por qué, y
cómo deshacerlo si algo se rompe.

## Resumen rápido de ficheros tocados/creados

| Fichero | Qué es | Se puede borrar / revertir sin miedo |
|---|---|---|
| `~/.config/caelestia/sync-rgb.py` | Script principal, se ejecuta en cada cambio de wallpaper/tema | Sí, hay backup: `sync-rgb.py.pre-argb-backup` |
| `~/.config/caelestia/argb-wave.py` | Demonio de la "ola" ARGB animada | Sí, bórralo y desactiva el servicio |
| `~/.config/systemd/user/argb-wave.service` | Unidad systemd que mantiene la ola corriendo | Sí, `systemctl --user disable --now argb-wave` |
| `/etc/xdg/quickshell/caelestia/services/Wallpapers.qml` | **Fichero del paquete `caelestia-shell`**, parcheado para sincronizar RGB durante la vista previa del wallpaper | Backup en `~/.config/caelestia/Wallpapers.qml.orig-backup` |

---

## 1. Bug: el teclado Akko nunca se sincronizaba

**Qué pasaba:** `sync-rgb.py` excluía el teclado a propósito (`if "Keyboard" in
dev.name: continue`), probablemente porque un intento anterior de incluirlo
lo apagaba en vez de ponerle color.

**Causa real:** el código forzaba el modo "Direct" asumiendo que siempre es
el índice `0` (`dev.set_mode(0)`). Eso es cierto para la RAM y la placa base,
pero en el teclado Akko el orden de modos es `Off, Direct, Breathing...` — el
índice `0` es "Off", no "Direct". Forzar el índice 0 apagaba el teclado.

**Arreglo:** buscar el modo "Direct" **por nombre** en vez de por índice fijo
(función `sync_openrgb`, bloque que llama a `dev.set_mode(direct_idx)`).

**Bug #2 relacionado:** incluso arreglado el modo, el color no se aplicaba.
La librería `openrgb-python` solo actúa en `dev.set_color()` si el modo
tiene `color_mode` `PER_LED` o `MODE_SPECIFIC`; el Akko reporta su modo
Direct como `RANDOM`, así que `dev.set_color()` es un no-op silencioso (sin
error, sin efecto). Arreglo: usar `zone.set_color()` en vez de
`dev.set_color()` — `Zone.set_color()` siempre manda el paquete sin mirar esa
bandera.

## 2. Barra LED lateral del teclado Akko — investigado, no implementado

Se investigó si se podía controlar por separado la barra lateral del Akko
5075B Plus. Conclusión: **no es posible con la versión actual de OpenRGB**.

- El teclado usa VID:PID `3151:4015`, gestionado por el driver genérico de
  OpenRGB `Controllers/EpomakerController` (compartido con otras marcas
  "rebrand" como Epomaker o Attack Shark, todas con el mismo PCB/chip).
- Ese driver solo expone **una zona, un LED** ("Keyboard LEDs") — no hay
  ninguna zona para la barra lateral.
- Según la FAQ oficial de Akko, la barra lateral se controla con un
  protocolo HID **distinto** al del teclado principal, solo accesible desde
  su driver propietario (Akko Cloud Driver) o mediante atajos de teclado
  (`Fn+Z` brillo, `Fn+X` velocidad, `Fn+Ctrl` efecto). Nadie ha volcado ese
  protocolo en OpenRGB.
- Se podría añadir con ingeniería inversa (captura USB + parche al driver +
  Merge Request), pero es un proyecto de varios días con resultado incierto
  (el mantenedor de OpenRGB tiene un backlog grande de dispositivos
  pendientes). Se descartó por no compensar frente al beneficio.

## 3. Base de carga / dongle del ratón MCHOSE K7 Ultra — protocolo descifrado

**Motivación:** el color de la base no cambiaba realmente aunque el script
no diera error (mismo patrón de fallo silencioso que el teclado).

**Cómo se descifró:** en vez de usar Windows, se aprovechó que la propia web
de configuración de MCHOSE usa WebHID/HID directo desde Linux. Se capturó el
tráfico USB real con:

```bash
sudo tshark -i usbmon1 -w /tmp/mchose.pcapng
```

mientras se cambiaba el color en la web, y luego se analizó el `.pcapng`
filtrando por transferencias de control (`usb.transfer_type == 0x02`), que
es donde van los comandos `SET_REPORT`/`GET_REPORT` reales.

**Trampas encontradas al filtrar** (por si se repite el proceso con otro
dispositivo):
- La mayoría del tráfico capturado es ruido: sondeo periódico de estado del
  dongle (batería, DPI), no relacionado con lo que haces en la web.
- Filtrar por `usb.idVendor`/`usb.idProduct` **no sirve** para tráfico en
  curso — esos campos solo aparecen en el paquete de enumeración inicial.
- Un filtro por "contiene la etiqueta HID Data" se comió justo el paquete
  que buscábamos: los `SET_REPORT` de control transfer no llevan esa
  etiqueta en Wireshark, aparecen como "Packet"/"USB Control" sin más.

**Protocolo encontrado y verificado:**
- `bmRequestType 0x21`, `bRequest 0x09` (SET_REPORT), `wValue 0x0311`
  (Report Type = Feature, Report ID = `0x11`), `wIndex 2` (interfaz 2),
  `wLength 21`.
- Payload de 20 bytes (antes del XOR): `[0x2B, 0x01, 0x06, 0x00, brillo(100),
  0x00, velocidad(3), modo(1=estático), 0x00, R,G,B (LED1), R,G,B (LED2),
  0,0,0,0,0]`, cifrado con XOR 0xFF byte a byte, con el Report ID `0x11` sin
  cifrar delante.
- Verificado byte a byte contra una captura real en azul puro (0,0,255):
  coincide exactamente.
- Se limitó el envío a los nodos `hidraw` de la **Interfaz 2** específicamente
  (filtro `":1.2" in link` sobre el `realpath` del dispositivo), para no
  escribir en interfaces HID que no son la de RGB.

**Pendiente de confirmar:** si la base es ARGB de verdad (dos zonas físicas
independientes) o RGB simple con un segundo campo de color sin uso real. Se
mandó un test con LED1=rojo/LED2=azul y se pidió confirmación visual — mira
el resultado de esa prueba antes de intentar hacerle un degradado propio a
la base (por ahora recibe un único color en ambos campos, igual que antes).

## 4. Degradado con la paleta del tema en RAM y ventiladores (ARGB)

Caelestia ya extrae una paleta completa (`primary`, `secondary`, `tertiary`,
`red`, `peach`, `yellow`, `green`, `sky`, `sapphire`, `lavender`, `mauve`,
etc.), no solo un color. Se aprovechó para dispositivos que son realmente
direccionables:

- **RAM** (`ENE DRAM` x2, 5 LEDs cada uno): degradado de 5 tonos.
- **Ventiladores** (cabezales `Aura Addressable 1` y `Aura Addressable 2` de
  la placa ASUS, 60 LEDs cada uno): degradado de 60 tonos.

**Explícitamente NO tocado** (siguen en color sólido, un único color, igual
que siempre):
- Teclado Akko (solo tiene 1 LED lógico en OpenRGB, no se puede repartir).
- Zona `Aura Mainboard` de la placa base (LEDs propios de la placa +
  cabezales RGB no direccionables, 4 LEDs) — no son "ventiladores".
- Base MCHOSE y tira MagicHome — no mencionados para este cambio.

**Cómo activar/desactivar:** en `sync-rgb.py`, la constante `RAINBOW_MODE`
(línea ~27). Ponerla a `False` vuelve al color sólido de siempre en todos
los dispositivos, sin tocar nada más.

**Verificación real hecha:** tras ejecutar el script, se consultó cada LED
individualmente vía OpenRGB (no solo el log) y se confirmó que RAM y
ventiladores tienen colores distintos por LED, mientras que teclado y
`Aura Mainboard` siguen con un único color uniforme.

## 5. Animación de "ola" ARGB en movimiento (RAM + ventiladores)

El degradado del punto 4 es estático — se recalcula solo cuando cambia el
wallpaper, pero no se mueve. Para tener una ola de verdad se necesitaba un
proceso corriendo continuamente (el hook de wallpaper es de un solo disparo,
no un bucle).

**Qué se creó:**
- `~/.config/caelestia/argb-wave.py`: bucle a ~12,5 fps que lee la paleta del
  tema en cada fotograma y hace *scroll* de un degradado cíclico (rojo →
  melocotón → amarillo → verde → cielo → zafiro → lavanda → malva → vuelta a
  rojo, sin costura) sobre la RAM y los dos cabezales de ventiladores.
  Vuelta completa cada 7 segundos (`CYCLE_SECONDS`, ajustable).
- `~/.config/systemd/user/argb-wave.service`: unidad de usuario, arranca
  solo, depende de `openrgb.service`, se reinicia solo si falla.

**Ya está activado.** Comandos útiles:

```bash
# Parar un rato (vuelve a arrancar al reiniciar sesión)
systemctl --user stop argb-wave.service

# Parar y que no vuelva a arrancar solo
systemctl --user disable --now argb-wave.service

# Ver que sigue vivo / ver logs
systemctl --user status argb-wave.service
journalctl --user -u argb-wave.service -f
```

Al estar corriendo constantemente, esta ola "gana" sobre el degradado
estático de `sync-rgb.py` en los mismos LEDs (los pisa cada ~80ms), así que
en la práctica solo importa si el demonio está parado.

## 6. Sincronizar el color durante la vista previa del wallpaper (parche a `caelestia-shell`)

**El problema:** al navegar por la lista de wallpapers (antes de pulsar
Enter), Caelestia solo calcula el esquema de color en memoria para pintar la
propia interfaz del shell (`caelestia wallpaper -p <ruta>` → `Colours.load(
text, true)`), pero **nunca** escribe `scheme.json` ni dispara el
`postHook` que ejecuta `sync-rgb.py`. Por diseño, la vista previa está
desconectada de todo lo demás — el RGB solo se actualiza al confirmar con
Enter (que sí llama a `caelestia wallpaper -f <ruta>` de verdad).

**Qué se hizo:** parchear el fichero real del paquete
`/etc/xdg/quickshell/caelestia/services/Wallpapers.qml` para que, cuando
llega el resultado de la vista previa, además dispare `sync-rgb.py` con esos
colores (con un debounce de 150ms para no lanzar un proceso por cada tecla
si te desplazas rápido). Las líneas añadidas están marcadas con el
comentario `// [claude-rgb-preview-patch]` para que sean fáciles de
localizar.

### ⚠️ Importante: esto se va a romper solo, y es normal

Ese fichero **pertenece al paquete `caelestia-shell`** (instalado con
`pacman`/`paru`), no a tu configuración personal. La próxima vez que
actualices ese paquete (`paru -Syu` o similar), el instalador **sobrescribirá
el fichero y el parche desaparecerá sin avisar** — la vista previa dejará de
sincronizar el RGB, sin ningún error visible, simplemente volverá al
comportamiento de "solo al confirmar con Enter".

**Si un día notas que la vista previa ya no sincroniza el RGB:** lo más
probable es que `caelestia-shell` se haya actualizado y se haya perdido el
parche. Comprueba con:

```bash
grep -c "claude-rgb-preview-patch" /etc/xdg/quickshell/caelestia/services/Wallpapers.qml
```

Si devuelve `0`, el parche se ha perdido y hay que volver a aplicarlo a mano
(pide ayuda para regenerarlo, o guarda una copia del fichero parcheado en un
sitio seguro para reaplicarlo tú mismo con `sudo cp`).

**Para revertir a como estaba de fábrica** (por ejemplo si no te convence o
da problemas):

```bash
sudo cp ~/.config/caelestia/Wallpapers.qml.orig-backup /etc/xdg/quickshell/caelestia/services/Wallpapers.qml
caelestia shell -k
caelestia shell -d
```

La copia de seguridad del original está en
`~/.config/caelestia/Wallpapers.qml.orig-backup` (no en `/tmp`, que se puede
borrar al reiniciar el sistema).

---

## Cómo volver TODO a como estaba antes de esta sesión

Por capas, de lo más reciente a lo más antiguo:

1. **Revertir la vista previa en directo:** ver comandos de la sección 6.
2. **Parar la ola ARGB:** `systemctl --user disable --now argb-wave.service`
   (opcionalmente borrar `~/.config/caelestia/argb-wave.py` y el `.service`).
3. **Quitar el degradado estático:** editar `sync-rgb.py` y poner
   `RAINBOW_MODE = False`, o restaurar el backup completo:
   ```bash
   cp ~/.config/caelestia/sync-rgb.py.pre-argb-backup ~/.config/caelestia/sync-rgb.py
   ```
   (Ojo: ese backup es *antes* del degradado pero *después* de los arreglos
   del teclado y el protocolo de la base MCHOSE — esos arreglos son bugs
   reales, no una preferencia estética, así que no debería haber motivo para
   revertirlos también.)
4. Los arreglos del teclado Akko y el protocolo de la base MCHOSE (secciones
   1 y 3) no tienen "modo antiguo" al que volver — eran bugs que impedían
   que esos dispositivos se sincronizaran en absoluto.
