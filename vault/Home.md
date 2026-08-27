---
tags: [moc, home, indice]
actualizado: 2026-08-27
---

# 🛸 LinuxRicing · Base de Conocimiento Maestro

Bienvenido a la bóveda de conocimiento y arquitectura de **Alberto** para el setup **LinuxRicing** (Arch Linux / CachyOS + Hyprland + Quickshell Caelestia + Material You).

Esta bóveda vive dentro del repositorio en [`LinuxRicing/vault/`](file:///home/alberviz/LinuxRicing/vault/) y se sincroniza automáticamente con Git.

---

## 🧭 Mapa de Navegación

```mermaid
graph TD
    Home[🏠 Home: Índice Central] --> Guia[📚 Guía de Obsidian para Alberto]
    Home --> Arq[🏛️ Arquitectura General del Setup]
    Home --> CentroRGB[🌈 Centro de Iluminación RGB (Proyecto Activo)]
    Home --> Refactor[🏗️ Plan de Unificación: Daemon rgbd]
    Home --> Roadmap[🔮 Roadmap Maestro de Innovaciones]
    Home --> Protocolo[🐭 Protocolo USB HID Base MCHOSE 8K]
    Home --> Backlog[📋 Backlog de Efectos y Mejoras]
```

---

## 📚 1. Guía de Uso y Sincronización
- [[Guía de Obsidian para Alberto|📚 Guía de Obsidian para Alberto]] — Qué es Obsidian, cómo usar enlaces `[[...]]`, etiquetas, diagramas y cómo sincronizarlo gratis con tu móvil u otros PCs con Git, Syncthing o Remotely Save.

---

## 🏛️ 2. Arquitectura del Sistema y Hardware
- [[Rice LinuxRicing/Arquitectura General del Setup|🏛️ Arquitectura General del Setup]] — Diagrama integral de Wayland, QML, Matugen, Spicetify, OpenRGB y los controladores USB.
- [[Rice LinuxRicing/Protocolo USB HID MCHOSE 8K|🐭 Protocolo USB HID · Base MCHOSE 8K]] — Ingeniería inversa de los 20 bytes del comando `0x2B`, Target IDs confirmados (`0x06`, `0x02`, `0x01`, `0x07`) y automatizaciones de carga.
- [[Rice LinuxRicing/Estado del Arte e Ingeniería Inversa en la Comunidad|🌐 Estado del Arte e Ingeniería Inversa]] — Análisis del ecosistema Open Source (OpenRGB, HID-BPF, por qué los dongles 8K usan ROM ARGB y telemetría Akko).
- [[Rice LinuxRicing/Iluminación - Estado actual|💡 Iluminación · Estado Actual]] — Detalle técnico de cada periférico (teclado Akko, placa ASUS TUF, RAM, tira MagicHome, ratón y base).

---

## 🚀 3. Proyectos Activos y Propuestas de Refactorización
- [[Rice LinuxRicing/Centro de Iluminación RGB|🌈 Centro de Iluminación RGB]] — *(Proyecto activo de Claude)*: Ventana overlay única para controlar toda la iluminación del setup con un clic.
- [[Rice LinuxRicing/Plan de Refactorización y Modularización (rgbd)|🏗️ Plan de Unificación · Daemon rgbd & rgbctl]] — Propuesta para fusionar los scripts sueltos en un único daemon modular con control de eventos, snapshots y cero colisiones.

---

## 🔮 4. Roadmaps y Backlogs de Innovaciones
- [[Rice LinuxRicing/Roadmap Maestro de Innovaciones|🔮 Roadmap Maestro de Innovaciones]] — Visión de futuro: Ambilight para la tira LED, letras sincronizadas en el escritorio (*Synced Lyrics*), temas dinámicos para Discord/Vencord y MangoHud, y perfiles de batería para portátil.
- [[Rice LinuxRicing/Backlog - Efectos de iluminación|📋 Backlog · Efectos de Iluminación]] — Lista detallada de ideas y funciones de iluminación priorizadas por coste y valor.

---

## 📥 5. Buzón de Ideas Rápidas
- [`Inbox/`](file:///home/alberviz/LinuxRicing/vault/Inbox/) — Carpeta para apuntes rápidos, enlaces o capturas sin ordenar. Claude y Gemini nos encargamos de procesarlos y archivarlos.
