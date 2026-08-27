---
tags: [moc]
---

# Home

Bóveda de conocimiento de **Alberto** para el setup **LinuxRicing** (Arch/CachyOS + Hyprland + Caelestia). Vive dentro del repositorio en `LinuxRicing/vault/` y se versiona con git junto al resto del rice.

## Áreas del Rice

- [[Rice LinuxRicing/Arquitectura General del Setup|🏛️ Arquitectura General del Setup]] — vista panorámica de la infraestructura, Wayland, QML, Matugen y Spicetify.
- [[Rice LinuxRicing/Protocolo USB HID MCHOSE 8K|🐭 Protocolo USB HID · Base MCHOSE 8K]] — desglose de los 20 bytes del comando `0x2B`, Target IDs confirmados (`0x06`, `0x02`, `0x01`, `0x07`) y automatizaciones de carga.
- [[Rice LinuxRicing/Centro de Iluminación RGB|Centro de Iluminación RGB]] — proyecto activo: ventana única para controlar todos los periféricos con luz.
- [[Rice LinuxRicing/Iluminación - Estado actual|Iluminación · Estado actual]] — cómo funciona hoy el RGB (scripts, protocolos, hooks).
- [[Rice LinuxRicing/Backlog - Efectos de iluminación|Backlog · Efectos de iluminación]] — ideas de funciones futuras, priorizadas y estimadas.

## Cómo se usa esta bóveda

- **Gemini & Claude** leen y escriben estos `.md` directamente desde el repositorio en `~/LinuxRicing/vault/`. No hay intermediarios: Obsidian detecta los cambios en disco y los renderiza en vivo al instante con grafos, tablas y diagramas Mermaid.
- `Inbox/` es para capturas rápidas sin ordenar.
- Cuando surja una idea de "esto se podría añadir en el futuro", va al backlog correspondiente, no al código.
