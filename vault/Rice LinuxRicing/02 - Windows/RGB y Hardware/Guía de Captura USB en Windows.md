---
tags: [guia, windows, usb, wireshark, captura, tutorial]
actualizado: 2026-08-27
---

# 🪟 Guía Paso a Paso: Captura USB en Windows y Sincronización

Esta guía está diseñada para que puedas hacer la captura del tráfico USB de tus periféricos (**Teclado Akko 5075B Plus**, **Base MCHOSE 8K**, etc.) en Windows usando el software oficial del fabricante y subirla a GitHub para que Gemini y Claude la analicen al volver a Linux.

```mermaid
sequenceDiagram
    autonumber
    actor Usuario
    participant Win as Windows + Akko Driver
    participant WS as Wireshark (USBPcap)
    participant Git as Repositorio GitHub
    participant Linux as LinuxRicing (Gemini/Claude)

    Usuario->>Win: Abre software oficial de Akko (muestra batería)
    Usuario->>WS: Inicia captura en USBPcap
    Win->>WS: Envía/Recibe paquetes HID de batería
    Usuario->>WS: Detiene captura y guarda "akko-battery-windows.pcapng"
    Usuario->>Git: git add, commit y push
    Git->>Linux: git pull al reiniciar en Linux
    Linux-->>Usuario: ¡Batería real decodificada e integrada!
```

---

## 🛠️ Paso 1: Clonar el Repositorio y Abrir Obsidian en Windows

1. Abre **PowerShell** o **Git Bash** en Windows.
2. Clona tu repositorio (si no lo tienes ya):
   ```powershell
   git clone https://github.com/Alberviz/LinuxRicing.git
   cd LinuxRicing
   ```
3. Si ya lo tenías clonado, actualízalo con:
   ```powershell
   git pull origin main
   ```
4. Abre **Obsidian** en Windows:
   - Haz clic en **"Open folder as vault"** *(Abrir carpeta como bóveda)*.
   - Selecciona la carpeta `LinuxRicing\vault`.

---

## 🦈 Paso 2: Instalar Wireshark con USBPcap

1. Descarga e instala **[Wireshark para Windows](https://www.wireshark.org/download.html)**.
2. ⚠️ **MUY IMPORTANTE durante el instalador:**
   - Cuando te pregunte por componentes adicionales, **marca la casilla `Install USBPcap`**.
   - Si te pide reiniciar el ordenador para cargar el controlador USBPcap, reinicia.

---

## 📡 Paso 3: Realizar la Captura del Teclado Akko en Modo 2.4 GHz

Para descifrar cómo el driver oficial de Akko se comunica con el dongle 2.4G (`PID 0x4011`) para leer la batería y cambiar las luces:

1. **Conecta únicamente el receptor 2.4G (Dongle USB)** al PC (el teclado en modo inalámbrico `Fn + Y`, sin cable USB conectado al PC).
2. Abre **Wireshark**:
   - En la lista de interfaces verás varias llamadas **`USBPcap1`**, **`USBPcap2`**, etc.
   - Haz doble clic en la interfaz USB correspondiente donde esté el dongle.
3. **Inicia la captura** (`Ctrl + E`).
4. Abre el software oficial **Akko Cloud Driver / Akko Driver**:
   - Deja que el programa reconozca el teclado en modo 2.4G y muestre el porcentaje de batería en pantalla.
   - Ve a la pestaña de **Iluminación (Lighting)**:
     - Cambia el color de la retroiluminación a un color llamativo (ej. Rojo o Azul).
     - Cambia el efecto de la **tira lateral (Side Strip)** a respiración o flujo.
     - Presiona "Aplicar" / "Save".
5. Vuelve a Wireshark y pulsa el botón rojo de **Detener Captura** (`Ctrl + E`).
6. Ve a **File** → **Save As...** *(Guardar como)*:
   - Guarda el archivo dentro de tu carpeta `LinuxRicing` con el nombre:
   - 👉 `akko-2.4g-rgb-battery-windows.pcapng`

---

## 🚀 Paso 4: Subir la Captura a GitHub

Abre tu terminal en Windows dentro de la carpeta `LinuxRicing` (PowerShell o Git Bash) y ejecuta:

```powershell
git add akko-2.4g-rgb-battery-windows.pcapng
git commit -m "feat: add Windows pcapng capture for Akko 5075B 2.4G battery and RGB"
git push
```

---

## 🐧 Paso 5: Al volver a Linux

Cuando reinicies en Linux:
1. Abre tu terminal y haz:
   ```bash
   cd ~/LinuxRicing && git pull
   ```
2. Escríbeme: *"Gemini, ya he subido la captura de Windows"* y nosotros nos encargamos de extraer el byte exacto y dejar tu widget de batería funcionando con datos 100% reales.
