---
fileClass: Backlog
tipo: tarea
estado: en-curso
prioridad: 1
area: hardware
origen: Alberto
esfuerzo: S
creado: 2026-10-21
tags:
  - backlog
---

# Tablet como segundo monitor con Sunshine y Moonlight

> [!TIP] Todo el software en tu PC ya está instalado y configurado
> Se ha creado la pantalla virtual nativa para la **Honor MagicPad 2** (resolución 3000×1920 a 144 Hz, escala 1.6), el servidor Sunshine con aceleración por GPU (NVENC RTX 4050) y el botón en los **Quick Toggles** de Caelestia Shell.

---

## 📱 Lo que te queda a ti por hacer (Solo 3 pasos rápidos)

### Paso 1: Instalar Moonlight en la Tablet
- Abre Google Play Store en tu **Honor MagicPad 2**.
- Busca e instala **Moonlight Game Streaming** (gratuita y de código abierto).

---

### Paso 2: Activar el modo Segundo Monitor en el PC
Puedes activarlo de cualquiera de estas dos formas:
- **Desde Caelestia Shell:** Abre los **Quick Toggles** y pulsa el botón con el icono de la tablet (`tablet_android`).
- **O desde la terminal:**
  ```bash
  caelestia-tablet-display on
  ```
*(Al activarlo, se creará el monitor virtual y se levantará el servicio Sunshine de fondo).*

---

### Paso 3: Emparejar la Tablet con el PC (Solo la primera vez)
1. Con la tablet y el PC conectados a la misma red Wi-Fi, abre la app **Moonlight** en la tablet.
2. Verás aparecer tu ordenador (`LinuxBeast` o IP `192.168.1.86`). Tócalo.
3. Moonlight te mostrará en la tablet un **PIN de 4 dígitos** (por ejemplo: `1234`).
4. Para emparejarlo, tienes dos opciones:
   - **Opción rápida por terminal:** Ejecuta en tu PC:
     ```bash
     caelestia-tablet-display pair 1234
     ```
     *(Sustituye `1234` por el PIN que te salga en la tablet).*
   - **Opción vía Web:** Abre en el navegador de tu PC [`https://localhost:47990`](https://localhost:47990), entra con usuario `alberto` y contraseña `alberto`, ve a la pestaña **PIN** e introduce el número.

---

### ¡Listo! 🎉
En la tablet, dentro de Moonlight, pulsa sobre **"Tablet Display (Honor MagicPad 2)"** (o "Desktop"). Inmediatamente verás tu segundo monitor a 144 Hz en la pantalla OLED de la tablet.

---

## ⚙️ Ajustes recomendados en la app Moonlight (Tablet)
En la app Moonlight de la tablet, entra a la rueda de **Ajustes** (arriba a la derecha) antes de conectar:
- **Resolución:** Selecciona *Nativa* o *3000x1920* (o 2560x1600).
- **Tasa de fotogramas (FPS):** Ponlo a **120 FPS** o **144 FPS** para aprovechar el refresco del panel OLED.
- **Tasa de bits (Bitrate):** Súbelo a **40 - 60 Mbps** para máxima nitidez de texto.
- **Modo de pantalla:** Pantalla completa.

---

## 🔌 Conexión por cable USB (Latencia 0 y carga)
Si no quieres usar Wi-Fi o estás fuera de casa:
1. Conecta la tablet al portátil por cable USB-C.
2. En la tablet, activa **Anclaje de red USB** (USB Tethering) en Ajustes de Red.
3. Moonlight detectará el PC por la red local directa del cable USB con latencia inferior a 2 ms.
