# Selector de perfil/códec Bluetooth (Nexus)

Dónde: Nexus → Bluetooth → ficha del dispositivo (`BtDeviceInfo.qml`), fila «Audio profile».
Solo aparece si el dispositivo está conectado y su tarjeta `bluez_card.*` tiene perfiles A2DP de sink.

## Piezas
- `configs/quickshell/caelestia/services/BluetoothAudioProfile.qml` (singleton):
  - `pactl -f json list cards` → `cards[<bluez_card.MAC_con_guiones_bajos>] = { active, profiles[] }`.
  - Filtra `a2dp-sink*` con `available=true` y `sinks>=1`, por prioridad. No ofrece `headset-head-unit*`.
  - `setProfile(address, profile)` → `pactl set-card-profile`, y refresca.
  - Refresco: `Timer` de 5 s solo mientras `watchers > 0` (la ficha lo incrementa al abrirse). Sin `FrameAnimation`.
  - Si `pactl` falla: `cards = {}` y `lastError`; la UI oculta el selector.
- `BtDeviceInfo.qml`: `Variants` de `MenuItem` + `SelectRow`.

## Por qué pactl
`Quickshell.Services.Pipewire` no expone perfiles de tarjeta.

## Verificación manual
```bash
C=bluez_card.84_AC_60_67_73_78
pactl set-card-profile $C a2dp-sink-sbc; pactl list sinks | grep codec   # "sbc"
pactl set-card-profile $C a2dp-sink;     pactl list sinks | grep codec   # "ldac"
```
Estado: cambio de perfil verificado con pactl; el selector en la UI aún no se ha probado con clics.
