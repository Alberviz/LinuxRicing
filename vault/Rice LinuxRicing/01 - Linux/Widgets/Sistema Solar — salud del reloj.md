---
tags: [rice, ui, sistema-solar, salud, amazfit, gts2]
estado: diseño
actualizado: 2026-10-26
---

# 🪐 Sistema Solar — salud del reloj (planeta «Cuerpo»)

Los datos del **Amazfit GTS 2** (pasos, sueño, entrenos, hábitos y FC) entran en el sistema
solar del escritorio como un planeta nuevo, «Cuerpo», fijo abajo a la derecha:

- **Arco de órbita** que se cierra hacia la meta de 10 000 pasos de hoy.
- **Terminador** día/noche = horas dormidas anoche sobre 7,5 h.
- **Lunas** = entrenos de openGym de la semana sobre 4.
- **7 cuentas** = racha de pasos de la semana. La marca encima de una cuenta = hábito hecho ese día.
- Sin datos o con datos atrasados se ve tenue o gris, nunca roto.

**Estado:** diseño propuesto (Fase 1). Rama `feat/solar-salud`.

## Documentación técnica (repo)

- Spec y decisión: [[docs/sistema-solar-salud-DISENO|Sistema solar · salud — diseño]]
- Mockup: `docs/sistema-solar-v3-mockup/salud-variantes.png`
- Escena en la que encaja: [[docs/sistema-solar-v3-DISENO|Sistema solar v3 — diseño]] ·
  [[Sistema Solar — decisiones v3]]
- Precedente del cometa de tareas: [[docs/sistema-solar-cometa-rediseno|Cometa de tareas]]

## Cadena de datos

`GTS 2 → Zepp → Health Connect → Google Health → gym-hub (Raspberry Pi) → /v1/summary →
widgets/gym-health → SolarSystemModel → HealthPlanet.qml`

Retraso típico: horas, por el tramo Zepp → Health Connect. FC en reposo, SpO₂ y kcal de
entreno llegan vacíos desde hace semanas, y el sueño a veces falta o llega fragmentado
(detalle en §2 de la spec).

## Vault del reloj (GTS2)

El conocimiento del reloj (sensores, Zepp OS, BLE, Gadgetbridge, scripting desde Linux) está
en el vault aparte `~/proyectos/GTS2/`:

- [Dashboard GTS 2](obsidian://open?path=%2Fhome%2Falberviz%2Fproyectos%2FGTS2%2F00%20-%20%F0%9F%A7%AD%20Dashboard%20%26%20Overview.md)
- [04.4 Salud del reloj en el escritorio (LinuxRicing)](obsidian://open?path=%2Fhome%2Falberviz%2Fproyectos%2FGTS2%2F04%20-%20Capacidades%20Ocultas%20y%20Proyectos%20Avanzados%2F04.4%20Salud%20del%20reloj%20en%20el%20escritorio%20%28LinuxRicing%29.md): la nota espejo en el vault del reloj
- [01.1 Especificaciones técnicas y sensores](obsidian://open?path=%2Fhome%2Falberviz%2Fproyectos%2FGTS2%2F01%20-%20Arquitectura%20y%20Hardware%2F01.1%20Especificaciones%20T%C3%A9cnicas%20y%20Sensores.md): de dónde salen pasos, sueño y FC
- [02.6 Scripting en Python y control desde Linux](obsidian://open?path=%2Fhome%2Falberviz%2Fproyectos%2FGTS2%2F02%20-%20Hacks%20y%20Casos%20de%20Superusuarios%2F02.6%20Scripting%20en%20Python%20y%20Control%20desde%20Linux.md)

> [!note] Enlaces entre vaults
> Obsidian no resuelve `[[wikilinks]]` entre vaults distintos. Por eso los enlaces a GTS2 son
> URIs `obsidian://open?path=…` con ruta absoluta. Si GTS2 se registra como vault en Obsidian,
> se abren ahí directamente.
