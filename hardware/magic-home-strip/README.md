# 💡 Tira LED Magic Home Wi-Fi

Tira LED de 12 V con controlador Wi-Fi Magic Home (chip Zengge/LEDnet). Se controla
por red, no por USB, así que no hay ingeniería inversa de HID: el protocolo ya lo
implementa la librería `flux_led`.

## Conexión

| Parámetro | Valor |
|---|---|
| Transporte | TCP |
| Puerto | `5577` |
| IP (esta red) | `192.168.0.136` |
| Librería | [`flux_led`](https://pypi.org/project/flux-led/) · fallback CLI `rgb/magichome-control` |

## Estado

| Capacidad | Estado |
|---|---|
| Encendido/apagado (`bulb.turnOn()` / `turnOff()`) | ✅ |
| Color sólido (`bulb.setRgb(r, g, b)`) | ✅ |
| Modo ambilight / screen-mirroring | ❌ (idea en `FUTURE_ROADMAP.md` §1) |

## Cómo se usa en el rice

- `rgb/magichome-control` — CLI (encender, color, off).
- `rgb/sync-rgb.py` — aplica el color Material You cuando cambia el wallpaper.
- Widget "Iluminación Ambiente" en `widgets/Background.qml`.

## Notas

- La IP puede cambiar si el router no la reserva por DHCP; conviene fijar reserva
  por MAC o usar el descubrimiento de `flux_led`.
- Es puramente decorativa/ambiental: no reporta batería ni telemetría.
