---
title: Diagnóstico y Handoff — Panel de WiFi en Caelestia
date: 2026-09-14
tags:
  - quickshell
  - qml
  - wifi
  - network
  - debugging
  - handoff
status: solucionado
solucion: "[[Arreglar panel de WiFi en Caelestia]]"
---

# 📶 Diagnóstico y Handoff — Panel de WiFi en Caelestia

> [!warning] ESTADO DEL PROBLEMA (DIAGNOSTICADO)
> El subsistema de red WiFi de Caelestia (Quickshell / QML) presenta **tres fallos críticos independientes** que impiden la conexión normal a redes nuevas:
> 1. En el **Centro de Control (Nexus)**, hacer clic sobre una red no guardada no abre ningún campo ni diálogo de contraseña (falla silenciosamente). La subpágina manual «Add network» sufre de un defecto de layout en su campo de contraseña, está forzada a modo «red oculta» y atada a `wpa-psk`.
> 2. En el **Popout rápido de la barra**, al conmutar a la vista de contraseña (`wirelesspassword`), el `Loader` de QML destruye el componente de red padre, dejando la referencia `network` en `null`. Al pulsar **Connect**, la función evalúa `if (!root.network) return;` y aborta en silencio absoluto sin enviar ningún comando a NetworkManager.
> 3. En ese mismo popout, las contraseñas largas **desbordan visualmente la tarjeta** debido a que no se usa un campo de texto nativo, sino un `ListView` horizontal que instancia un rectángulo por carácter sin `clip`, sin ancho máximo y centrado con respecto al contenedor.

---

## 📋 1. Resumen Ejecutivo (para Alberto)

El sistema de WiFi actual funciona bien para **redes que ya tenías guardadas antes** (por ejemplo configuradas desde la consola o un instalador anterior), pero está **completamente roto para conectarse a redes nuevas**. 

Esto no se debe a un problema del sistema operativo ni de NetworkManager, sino a **defectos de código puro en los componentes QML heredados del proyecto base (`caelestia-dots`)**:
- En el panel grande (Nexus), simplemente **se les olvidó programar el diálogo o pantalla de contraseña** cuando haces clic en una red de la lista: el código espera un objeto que no existe y descarta la petición en silencio.
- En el menú rápido de la barra, al abrir la pantalla de contraseña, la ventana anterior de la lista se descarga de la memoria y **borra en el acto los datos de la red a la que querías conectarte**. Cuando le das a «Connect», el botón ve que no tiene red asignada y no hace absolutamente nada.
- El desborde de contraseñas ocurre porque, en vez de usar una caja de texto estándar para contraseñas (que oculta las letras con puntos y hace scroll horizontal si es larga), crearon un diseño inventado que dibuja un circulito individual por cada letra. A partir de 16 caracteres, los circulitos no caben y se salen literalmente flotando fuera de la ventana.

Todo este código viene **100% intacto del proyecto original upstream (`0acbc27`)**: nadie en este repositorio lo había modificado ni intentado arreglar antes en commits de git.

---

## 🏛️ 2. Arquitectura de los Flujos de Conexión

Ambos flujos (Centro de Control grande vs. Popout rápido) intentan comunicarse con el mismo backend, pero la capa de presentación y el paso de estado entre vistas difieren sustancialmente:

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                 NetworkManager (nmcli)                  │
                  └───────────────────────────▲─────────────────────────────┘
                                              │
                                              │ Process (CLI)
                                              │
                  ┌───────────────────────────┴─────────────────────────────┐
                  │          services/Nmcli.qml (Singleton backend)         │
                  └───────────────────────────▲─────────────────────────────┘
                                              │
                                              │ invocaciones directas
                                              │
                  ┌───────────────────────────┴─────────────────────────────┐
                  │         utils/NetworkConnection.qml (Helper)            │
                  └─────────────────▲─────────────────────▲─────────────────┘
                                    │                     │
                    handleConnect() │                     │ handleConnect() + callback
                                    │                     │
       ┌────────────────────────────┴────────┐   ┌────────┴──────────────────────────┐
       │   FLUJO 1: CENTRO DE CONTROL NEXUS  │   │     FLUJO 2: POPOUT RÁPIDO BARRA  │
       │                                     │   │                                   │
       │ modules/nexus/pages/NetworkPage.qml │   │ modules/bar/popouts/Content.qml   │
       │ └─ common/NetworkList.qml           │   │ ├─ Popout "network" (Network.qml) │
       │ └─ network/AddNetworkPage.qml       │   │ └─ Popout "wirelesspassword"      │
       │                                     │   │    (WirelessPassword.qml)         │
       └─────────────────────────────────────┘   └───────────────────────────────────┘
```

### Componentes involucrados
1. **`services/Nmcli.qml`**: Singleton que corre en background. Es el motor principal: ejecuta comandos `nmcli` mediante el tipo `Process` de Quickshell (`Quickshell.Io`), parsea la salida de texto y mantiene colecciones de objetos `AccessPoint` y `EthernetDevice`. También monitoriza cambios de estado con `nmcli monitor`.
2. **`utils/NetworkConnection.qml`**: Objeto singleton pensado como «fuente de verdad» intermedia. Dispone de tres métodos:
   - `handleConnect(network, session, onPasswordNeeded)`
   - `connectToNetwork(network, session, onPasswordNeeded)`
   - `connectWithPassword(network, password, onResult)`
3. **`services/NetworkUsage.qml`**: **Confirmado:** No gestiona conexiones ni hardware WiFi. Su única función es leer `/proc/net/dev` periódicamente para calcular velocidades de subida/bajada y transferencias acumuladas destinadas a las gráficas del Dashboard.

---

## 🔍 3. Diagnóstico Exhaustivo Síntoma por Síntoma

---

### 🚨 Síntoma 1: Panel Completo (Nexus) no permite introducir contraseña para redes nuevas; "Add network" roto

#### 📍 Causa Raíz 1.1: Ausencia total de flujo de contraseña para redes escaneadas
- **Archivos y líneas**:
  - `configs/quickshell/caelestia/modules/nexus/common/NetworkList.qml`: líneas 62–67
  - `configs/quickshell/caelestia/utils/NetworkConnection.qml`: líneas 76–94
- **Mecanismo del fallo**:
  En `NetworkList.qml`, cuando el usuario hace clic sobre una red disponible que no está activa (`!modelData.active`), se ejecuta:
  ```qml
  onClicked: {
      if (!modelData.active) {
          NetworkConnection.handleConnect(modelData);
          currentSelected = true;
          root.networkSelected(modelData);
      } ...
  }
  ```
  Nótese que invoca `NetworkConnection.handleConnect(modelData)` pasando **únicamente el primer parámetro**. Los parámetros `session` y `onPasswordNeeded` son `undefined`.
  
  En `NetworkConnection.qml`:
  ```qml
  Nmcli.connectToNetworkWithPasswordCheck(network.ssid, network.isSecure, result => {
      if (result.needsPassword) {
          ...
          if (session && session.network) {
              session.network.showPasswordDialog = true;
              session.network.pendingNetwork = network;
          } else if (onPasswordNeeded) {
              onPasswordNeeded(network);
          }
      }
  }, network.bssid);
  ```
  Como `session` es `undefined` y `onPasswordNeeded` es `undefined`, al descubrir que la red requiere contraseña (`result.needsPassword == true`), **el código no hace nada**. Se descarta silenciosamente.
  En todo el módulo Nexus **no existe ninguna ventana modal, overlay ni subpágina de contraseña** asociada al listado de redes. El usuario hace clic y la interfaz se queda congelada sin responder.

#### 📍 Causa Raíz 1.2: Fallo en la subpágina manual «Add network» (`AddNetworkPage.qml`)
- **Archivos y líneas**:
  - `configs/quickshell/caelestia/modules/nexus/pages/network/AddNetworkPage.qml`: líneas 104, 142–181
  - `configs/quickshell/caelestia/services/Nmcli.qml`: líneas 653–691 (`addHiddenNetwork`)
- **Mecanismo del fallo**:
  1. **Defecto de anclaje vertical del campo de contraseña**:
     `passwordField` está contenido dentro de un `Item` con `implicitHeight: root.secured ? passwordField.implicitHeight : 0` (línea 145). Sin embargo, `passwordField` (líneas 167–180) solo tiene declarados:
     ```qml
     anchors.left: parent.left
     anchors.right: parent.right
     ```
     No tiene `anchors.top`, no tiene `anchors.bottom`, no tiene `anchors.fill: parent` y no define `height`. Al no ser hijo directo de un `Layout` (es hijo de un `Item` plano), la altura de `passwordField` colapsa a 0 o queda desvinculada del layout, impidiendo el foco y la interacción correcta del cursor.
  2. **Forzado a red oculta por defecto**:
     La propiedad `hiddenToggle.checked` viene por defecto en `true` (línea 104). Al pulsar Connect, ejecuta `Nmcli.addHiddenNetwork(..., hidden: true)`. La creación de un perfil con `802-11-wireless.hidden yes` para un punto de acceso estándar que sí emite beacon provoca que la negociación falle o demore excesivamente.
  3. **Forzado rígido a `wpa-psk`**:
     `addHiddenNetwork` hardcodea `802-11-wireless-security.key-mgmt wpa-psk`. Si la red del usuario es WPA3 Personal (SAE) o mixta WPA2/WPA3, NetworkManager rechaza la conexión con error de autenticación.
  4. **Borrado prematuro del perfil**:
     `onSubPageClosed` (líneas 63–70) ejecuta `Nmcli.forgetNetwork(ssid)` si `root.success` es falso. Si la conexión tarda más de la cuenta y el usuario retrocede o la subpágina se cierra, el perfil se autodestruye en segundo plano.

#### 💡 Propuesta de Fix para Síntoma 1
1. **Crear una subpágina de contraseña en Nexus**: Añadir una subpágina (por ejemplo `ConnectPasswordPage.qml` o un modal dialog) en `PageCompRegistry.qml` bajo `StackPage` de Network.
2. **Conectar `NetworkList.qml`**: Al detectar que `modelData` es segura y no tiene perfil guardado (`!Nmcli.hasSavedProfile(modelData.ssid)`), no llamar a `handleConnect` a ciegas; almacenar el SSID/objeto en `nState` y abrir la subpágina de contraseña correspondiente.
3. **Arreglar `AddNetworkPage.qml`**:
   - Poner `anchors.fill: parent` en `passwordField` dentro del contenedor `Item`, o eliminar el `Item` intermedio y controlar `visible: root.secured` directamente con `Layout.fillWidth: true`.
   - Cambiar `hiddenToggle.checked: false` por defecto.
   - En `Nmcli.addHiddenNetwork`, si la red no es oculta, usar `nmcli device wifi connect <ssid> password <password>` que auto-negocia el protocolo de seguridad (WPA2/WPA3) en vez de forzar `wpa-psk`.

---

### 🚨 Síntoma 2: Popout rápido no conecta al pulsar "Connect" (falla en silencio)

#### 📍 Causa Raíz 2.1: Destrucción por ciclo de vida de `Loader` y pérdida de `root.network`
- **Archivos y líneas**:
  - `configs/quickshell/caelestia/modules/bar/popouts/Content.qml`: líneas 34–91, 166–186
  - `configs/quickshell/caelestia/modules/bar/popouts/Network.qml`: líneas 136–141, 366–374
  - `configs/quickshell/caelestia/modules/bar/popouts/WirelessPassword.qml`: líneas 95–116, 209–236, 500–505
- **Mecanismo del fallo**:
  En `Content.qml`, los popouts se gestionan mediante el componente inline `Popout: Loader`:
  ```qml
  component Popout: Loader {
      id: popout
      required property string name
      readonly property bool shouldBeActive: root.popouts.currentName === name
      ...
      states: State {
          name: "active"
          when: popout.shouldBeActive
          PropertyChanges {
              popout.active: true
              popout.opacity: 1
          }
      }
  }
  ```
  Cuando el usuario pulsa en una red en `Network.qml`, se ejecuta:
  ```qml
  root.passwordNetwork = network;
  root.showPasswordDialog = true;
  root.popouts.currentName = "wirelesspassword";
  ```
  Al cambiar `currentName` a `"wirelesspassword"`:
  1. `networkPopout.shouldBeActive` pasa a ser `false`.
  2. El `Loader` `networkPopout` se desactiva y **destruye inmediatamente su contenido (`Network.qml`)**.
  3. En `Content.qml` línea 52:
     ```qml
     network: (networkPopout.item as Network)?.passwordNetwork ?? null
     ```
     Al destruirse `networkPopout.item`, `network` se convierte en `null`.
  4. Por si fuera poco, `Network.qml` (líneas 369–372) incluye un disparador de autodestrucción:
     ```qml
     if (root.popouts.currentName !== "wirelesspassword" && root.showPasswordDialog) {
         root.showPasswordDialog = false;
         root.passwordNetwork = null;
     }
     ```
  5. En `WirelessPassword.qml`, el botón `connectButton` (líneas 500–504) tiene la siguiente comprobación inicial:
     ```qml
     onClicked: {
         if (!root.network || connecting) {
             return;
         } ...
     }
     ```
  **Al ser `root.network == null`, la función sale inmediatamente sin hacer nada.** No emite log, no llama a ningún servicio, no cambia de estado. Falla en silencio absoluto.
  *(El autor original intentó remendar esto añadiendo un temporizador de 50ms en las líneas 209–236 para reintentar obtener la propiedad navegando por `root.parent?.parent?.parent`, pero dado que el elemento ya fue descargado por el Loader, el rescate falla).*

#### 📍 Causa Raíz 2.2: Defectos en el backend `Nmcli.qml` al procesar la contraseña
- **Archivos y líneas**:
  - `configs/quickshell/caelestia/services/Nmcli.qml`: líneas 420–424, 442, 449–474, 1459–1524
  - `configs/quickshell/caelestia/modules/bar/popouts/WirelessPassword.qml`: líneas 607–619
- **Mecanismo del fallo**:
  Aun en el hipotético caso de que `root.network` sobreviviera a la destrucción del Loader:
  1. `Nmcli.connectWireless` detecta que el objeto tiene `bssid` y salta a `createConnectionWithPassword`:
     ```qml
     if (password && password.length > 0 && hasBssid) {
         const bssidUpper = bssid.toUpperCase();
         createConnectionWithPassword(ssid, bssidUpper, password, callback);
         return;
     }
     ```
  2. `createConnectionWithPassword` intenta crear una conexión bloqueada a ese BSSID exacto (`802-11-wireless.bssid`) y forzada a `wpa-psk`. Si el router utiliza roaming (band steering 2.4/5GHz con mismo SSID) o seguridad WPA3, la conexión falla.
  3. En `Nmcli.qml` línea 442, la condición `else if (result.success && callback) {}` contiene un **bloque vacío**; no invoca el callback con el resultado.
  4. El temporizador `connectionCheckTimer` en `Nmcli.qml` (línea 1461) tiene un timeout de tan solo **4000 ms (4 segundos)**. La negociación WPA y la asignación de DHCP en NetworkManager suelen tardar entre 3 y 7 segundos. A los 4 segundos, el timer da la conexión por fallida y emite la señal `connectionFailed(ssid)`.
  5. Al recibir `connectionFailed`, `WirelessPassword.qml` (línea 616) ejecuta `Nmcli.forgetNetwork(ssid)`, borrando de un plumazo la conexión que todavía se estaba negociando.

#### 💡 Propuesta de Fix para Síntoma 2
1. **Persistencia del estado de la red seleccionada**:
   Mover la propiedad `passwordNetwork` fuera de `Network.qml` (que se destruye) y alojarla en un estado persistente: o bien en `PopoutState.qml`, o bien como propiedad directa en `Content.qml`, o en `Nmcli.pendingPasswordTarget`. De este modo, la transición entre popouts no destruye el objetivo.
2. **Reemplazar la creación manual de perfiles con BSSID en `Nmcli.qml`**:
   Sustituir la llamada forzada a `createConnectionWithPassword` con el comando estándar y robusto de NetworkManager:
   `nmcli device wifi connect "<ssid>" password "<password>"`
   NetworkManager se encarga nativamente de seleccionar el BSSID óptimo, auto-detectar WPA2/WPA3 y persistir el perfil con el gestor de claves adecuado.
3. **Aumentar el timeout de conexión en `Nmcli.qml`**:
   Ampliar `connectionCheckTimer.interval` de 4000ms a 12000–15000ms para permitir handshakes WiFi y DHCP sin falsos positivos de timeout.

---

### 🚨 Síntoma 3: Desbordamiento visual de contraseñas largas en el popout rápido

#### 📍 Causa Raíz 3.1: Implementación visual con `ListView` no elástica y sin contención
- **Archivos y líneas**:
  - `configs/quickshell/caelestia/modules/bar/popouts/WirelessPassword.qml`: líneas 259–270, 389–467
- **Mecanismo del fallo**:
  Para introducir la contraseña no se utilizó un `StyledTextField` ni un `TextInput` estándar con `echoMode: TextInput.Password`. En su lugar, se construyó un componente artesanal:
  1. Un `FocusScope` invisible (`passwordContainer`) captura las pulsaciones de tecla en un buffer de texto `passwordBuffer`.
  2. Para representar los caracteres en pantalla, se colocó un `ListView` horizontal (`charList`):
     ```qml
     ListView {
         id: charList
         readonly property int fullWidth: count * (implicitHeight + spacing) - spacing
         anchors.centerIn: parent
         implicitWidth: fullWidth
         implicitHeight: Tokens.font.body.medium.pointSize
         orientation: Qt.Horizontal
         interactive: false
         model: ScriptModel {
             values: passwordContainer.passwordBuffer.split("")
         }
         delegate: StyledRect {
             implicitWidth: implicitHeight
             implicitHeight: charList.implicitHeight
             color: Colours.palette.m3onSurface
             radius: Tokens.rounding.medium / 2
             ...
         }
     }
     ```
  3. **El mecanismo de desbordamiento**:
     - Cada carácter genera un `StyledRect` cuadrado de aproximadamente 14 px de ancho + espaciado (~4 px) = ~18 px por carácter.
     - `charList` tiene `implicitWidth: fullWidth`, creciendo indefinidamente a medida que se teclea.
     - No tiene `clip: true`, ni `passwordContainer` tiene `clip: true`, ni `content` tiene `clip: true`.
     - `charList` tiene `anchors.centerIn: parent`.
     - El contenedor `StyledRect` de la tarjeta tiene un ancho fijo de 400 px (`Layout.preferredWidth: 400`).
     - Cuando la contraseña supera los 15–18 caracteres (muy común en claves WiFi de routers modernos, que suelen tener de 20 a 32 caracteres alfanuméricos), el ancho acumulado de los puntos excede los 350 px utilizables.
     - Al estar centrado (`anchors.centerIn: parent`), la lista de puntos se desborda simétricamente hacia la izquierda y hacia la derecha, dibujando los puntos fuera de los bordes redondeados del diálogo y flotando sobre el fondo de la pantalla.

#### 💡 Propuesta de Fix para Síntoma 3
Existen dos alternativas claras de corrección:
- **Alternativa A (Recomendada, más robusta y estándar)**: Reemplazar el `FocusScope` + `charList` artesanal por un `StyledTextField` nativo:
  ```qml
  StyledTextField {
      id: passwordField
      Layout.fillWidth: true
      echoMode: TextInput.Password
      placeholderText: qsTr("Password")
      leadingIcon: "key"
      // Maneja internamente el scroll horizontal del texto, elide, selección y foco
  }
  ```
  Esto unifica el aspecto visual con el resto de campos de Caelestia (como los de Nexus o búsqueda) y elimina de raíz el problema de cálculo de tamaño.
- **Alternativa B (Mantener los puntos Material pero conteniéndolos)**:
  Si se desea mantener la estética de puntos discretos:
  1. Poner `clip: true` en `passwordContainer`.
  2. Limitar `charList.width = Math.min(fullWidth, passwordContainer.width - Tokens.padding.large * 2)`.
  3. Habilitar `interactive: false` pero orientar el scroll hacia el final (`positionViewAtEnd()`) en cada cambio de texto para que los últimos caracteres introducidos se mantengan visibles dentro de los límites de la tarjeta.

---

## 📜 4. Historial de Commits e Intentos Previos en el Repositorio

Para determinar si este fallo surgió tras una regresión reciente o si ya se había intentado solucionar, se realizó un rastreo exhaustivo en el historial de Git:

```bash
git log --all --follow --oneline -- configs/quickshell/caelestia/modules/nexus/pages/network/
git log --all --follow --oneline -- configs/quickshell/caelestia/modules/bar/popouts/Network.qml
git log --all --follow --oneline -- configs/quickshell/caelestia/modules/bar/popouts/WirelessPassword.qml
git log --all --follow --oneline -- configs/quickshell/caelestia/services/Nmcli.qml
git log --all --follow --oneline -- configs/quickshell/caelestia/utils/NetworkConnection.qml
```

### Hallazgo Clave
- **Todos los archivos mencionados fueron importados en el commit inicial:**
  `0acbc27` (*"feat: complete ricing system with Spicetify sync, multi-widget deck, peripheral alerts, installer, and documentation"*).
- **Ninguno de los archivos de red ha recibido modificaciones posteriores** en ninguna rama del repositorio.
- Una comparación directa (`diff -u`) entre los archivos del repositorio y los desplegados en `~/.config/quickshell/caelestia/` demostró que son **100% idénticos**.
- Búsquedas en las notas del Vault (`vault/`) y en planes de diseño (`docs/plans/`) confirman que **no existe documentación previa de intentos de arreglo**.
- **Conclusión**: El código actual viene **intacto del upstream de `caelestia-dots`**. Los tres fallos son bugs de diseño originales del autor del dotfile que nunca llegaron a ser pulidos.

---

## 📋 5. Lista Priorizada de Tareas de Fix Recomendadas

Para incorporar ordenadamente este trabajo al backlog vivo (`vault/🎯 Hoy.md` / `vault/Backlog/`), se desglosan las tareas en cuatro unidades independientes:

| Prioridad | Tarea / Título sugerido | Descripción | Esfuerzo |
|---|---|---|:---:|
| **P1** | **Fix(wifi): Persistencia de `network` y corrección de conexión en Popout rápido** | 1. Mover la referencia de la red a conectar a un estado persistente (ej: `PopoutState` o `Content.qml`) para que no se pierda al descargar `Network.qml`.<br>2. Corregir `WirelessPassword.qml` para que use el objeto persistido y valide antes de conectar.<br>3. En `Nmcli.qml`, usar `nmcli device wifi connect` directo en vez de pinning por BSSID manual. Aumentar timeout a 12s. | **M** |
| **P2** | **Fix(wifi): Sustituir `charList` por `StyledTextField` en `WirelessPassword.qml`** | Eliminar el `ListView` de puntos artesanales que desborda la tarjeta. Reemplazarlo por un `StyledTextField` con `echoMode: TextInput.Password` con `Layout.fillWidth: true`, leading icon `"key"` y botón de mostrar/ocultar contraseña opcional. | **S** |
| **P3** | **Fix(wifi): Diálogo/Subpágina de contraseña para redes escaneadas en Nexus** | Implementar la vista o modal de petición de contraseña en Nexus cuando el usuario pulse sobre una red con candado que no esté guardada, pasando el callback o invocando `NetworkConnection.connectWithPassword`. | **M** |
| **P4** | **Fix(wifi): Corrección de layout y modo broadcast en `AddNetworkPage.qml`** | 1. Corregir anclajes verticales (`anchors.fill: parent`) de `passwordField`.<br>2. Cambiar `hiddenToggle.checked` a `false` por defecto.<br>3. Adaptar `addHiddenNetwork` para soportar redes no ocultas y tipos WPA3/automáticos. | **S** |

---

## 🔎 6. Investigación en el repo oficial upstream (2026-09-14)

Antes de considerar un PR propio, se investigó si `caelestia-dots/shell` ya tenía estos
bugs documentados o resueltos. Resultado: **sí, hay trabajo en curso, pero nada mergeado
todavía** (a fecha de esta sesión):

| # | Título | Estado | Relación con nuestro caso |
|---|---|---|---|
| [issue #1806](https://github.com/caelestia-dots/shell/issues/1806) | Nexus no pide contraseña para redes nuevas | Cerrado (por PR #1869) | Nuestro Síntoma 3, palabra por palabra |
| [PR #1869](https://github.com/caelestia-dots/shell/pull/1869) | `fix(nexus): prompt for password when connecting to unsaved networks` | Abierto, sin mergear | Enfoque **más simple** que el nuestro inicial: elimina la rama especial de "perfil guardado" en vez de parchearla, y añade protección contra páginas de contraseña duplicadas |
| [issue #1934](https://github.com/caelestia-dots/shell/issues/1934) | Perfil WiFi "secretless" atascado + Forget falla con nombres sufijados | Abierto | Bug real adicional que nuestros 4 fixes originales NO cubrían — lo trajimos aparte |
| [PR #1881](https://github.com/caelestia-dots/shell/pull/1881) | `fix(services): stop corrupting wifi profiles on connect` | Abierto, sin mergear | Ataca la causa raíz de #1934 (el propio sondeo de contraseña de nmcli crea perfiles rotos) con limpieza automática diferida — más elegante que un parche puntual |
| [PR #1172](https://github.com/caelestia-dots/shell/pull/1172) | Fix independiente para "Forget Network" con nombres sufijados | Abierto | Confirma que nuestro fix de `savedProfileNameFor` va en la línea correcta — otro contribuidor llegó a la misma solución por su cuenta |
| [PR #1926](https://github.com/caelestia-dots/shell/pull/1926) (draft) | Migrar todo el backend de red de `nmcli` a los modelos nativos C++ de Quickshell | Draft, bloqueado por una dependencia de Quickshell aún no mergeada | Reescritura mayor, **no** se trae ahora — demasiado prematura/arriesgada, pero a vigilar a futuro |

**Decisión tomada**: en vez de mantener nuestra implementación original de los
síntomas 2 (mitad backend) y 3, se **reconcilió la rama con los enfoques de PR #1869 y
PR #1881**, adoptando su diseño (más simple, ya revisado por varios usuarios
independientes) y conservando nuestras mejoras propias que ningún PR upstream cubre: el
fix visual del desbordamiento de contraseñas y el arreglo de layout de "Add network".
Ver commits `852f8c3` (reconciliación) y `4a951f2` (fix de perfiles con sufijo,
compatible y complementario a PR #1881).

**Implicación para el futuro PR upstream**: como #1869 y #1881 ya están propuestos por
otros contribuidores, el PR que tendría sentido abrir desde este repo NO es uno que
compita con esos, sino a lo sumo: (a) comentar en esos PRs confirmando que funcionan
bien en un tercer setup (igual que ya hizo un usuario en #1869), y (b) proponer aparte
solo lo que de verdad es nuestro y no está cubierto: el fix visual de
`WirelessPassword.qml` y el de `AddNetworkPage.qml`.

---

## ✅ 7. Solución Implementada (2026-09-14)

Los 4 fixes se implementaron con un agente de Gemini (`gemini-3.8-flash-high` vía `agy`),
orquestado por Claude, en la rama `feat/wifi-panel-fixes`. El shell recargó limpio
(`INFO: Configuration Loaded`) tras cada bloque de cambios. Pendiente de **prueba
manual real por Alberto** (conectando a redes de verdad) antes de mergear.

Commits (en orden):
- `a5a84ff` — `fix(caelestia): persistencia de red seleccionada en popout y conexion robusta nmcli`
- `5892bb9` — `fix(caelestia): sustituir puntos artesanales por StyledTextField en WirelessPassword`
- `02e2675` — `feat(caelestia): flujo y subpagina de contrasena para redes nuevas en Nexus`
- `69f8523` — `fix(caelestia): layout de contrasena y modo broadcast por defecto en AddNetworkPage`
- `4a951f2` — `fix(caelestia): recuperar perfiles wifi rotos sin secretos y resolver nombres con sufijo` (basado en el patch del issue upstream #1934)
- `852f8c3` — `refactor(caelestia): reconciliar flujo wifi y limpieza de perfiles con PRs upstream` (adopta el diseño de PR #1869 y PR #1881, ver §6)

Detalle de cada fix:
- **Popout rápido no conectaba**: la red seleccionada ahora se guarda en
  `PopoutState.passwordNetwork` (sobrevive a que el `Loader` destruya `Network.qml`),
  en vez de perderse. `Nmcli.qml` dejó de forzar pinning manual a BSSID + `wpa-psk` y
  usa `nmcli device wifi connect "<ssid>" password "<password>"` (NetworkManager
  autonegocia WPA2/WPA3), con el timeout de verificación subido de 4s a 13s y los
  callbacks vacíos corregidos para que sí se invoquen.
- **Desbordamiento de contraseñas largas**: el `ListView` artesanal de puntos por
  carácter en `WirelessPassword.qml` se sustituyó por el `StyledTextField` nativo del
  sistema de diseño (mismo componente que usa el resto de Caelestia), con
  `echoMode: Password` — hace scroll interno en vez de desbordar la tarjeta.
- **Nexus no pedía contraseña para redes nuevas**: nueva subpágina
  `ConnectPasswordPage.qml` (registrada como subpágina 7 en `PageCompRegistry.qml`),
  enlazada desde `NetworkList.qml` cuando la red pulsada es segura y no tiene perfil
  guardado.
- **`AddNetworkPage.qml` roto**: campo de contraseña con `anchors.fill: parent` +
  `clip: true` (ya no colapsa a altura 0), `hiddenToggle` ahora empieza en `false`, y
  se quitó el borrado prematuro del perfil al cerrar la subpágina.
- **Perfiles WiFi rotos/atascados** (tras investigar issues/PRs upstream, ver §6): se
  simplificó `NetworkConnection.qml` para que toda conexión segura pase siempre por
  `connectToNetworkWithPasswordCheck` (sin la bifurcación frágil de "perfil guardado"),
  y `Nmcli.qml` ahora borra automáticamente, 3s después, los perfiles fantasma que el
  propio sondeo de contraseña de nmcli deja tirados sin secreto. `forgetNetwork`
  también resuelve nombres de perfil con sufijo automático (`"Mi Red 1"`).

**Nota para Alberto**: todo el código afectado venía intacto del upstream
[`caelestia-dots/shell`](https://github.com/caelestia-dots/shell) (GPL-3.0) — el repo
real donde vive el código fuente de Caelestia (`caelestia-dots/caelestia`, enlazado en
nuestro README, es el proyecto "paraguas"/dotfiles, no el shell en sí). Nunca se había
tocado ahí. Ver §6 para el estado real de esto en upstream.

---

## 🤖 8. Prompt de Implementación para Claude (Listo para Copiar)

```markdown
Hola Claude. Necesito que implementes la solución definitiva a los problemas del panel de WiFi en Caelestia (Quickshell / QML) dentro del repo LinuxRicing.

Por favor lee primero el informe de diagnóstico exhaustivo disponible en:
`vault/Diagnóstico y Handoff — Panel de WiFi en Caelestia.md`

### Resumen de los problemas a solucionar:
1. **Popout rápido (`modules/bar/popouts/`)**:
   - `Content.qml` descarga `networkPopout` al conmutar a `wirelesspassword`, dejando `network` en `null`. Al pulsar Connect, `WirelessPassword.qml` aborta silenciosamente.
   - El backend `Nmcli.qml` tiene timeouts muy agresivos (4s) y hace un pinning erróneo de BSSID y `wpa-psk`.
   - `charList` en `WirelessPassword.qml` desborda visualmente la tarjeta con contraseñas de más de 16 caracteres. Sustitúyelo por un `StyledTextField` con `echoMode: TextInput.Password`.
2. **Centro de Control Nexus (`modules/nexus/`)**:
   - Al pulsar en una red no guardada en `NetworkList.qml`, no se pide contraseña porque no existe flujo/diálogo implementado en Nexus.
   - `AddNetworkPage.qml` tiene roto el anclaje del campo de contraseña y fuerza la red a modo "oculta" y "wpa-psk".

### Reglas de trabajo obligatorias:
- Crear una rama dedicada (ej: `feat/wifi-panel-fixes`).
- Mantener idénticas las copias espejo si las hubiera.
- Sincronizar siempre a `~/.config/quickshell/caelestia/` y reiniciar el shell con:
  `caelestia shell -k 2>/dev/null || pkill -f "qs -c caelestia" 2>/dev/null || true; sleep 1; caelestia shell -d`
- Comprobar que arranque limpio con `INFO: Configuration Loaded`.
```
