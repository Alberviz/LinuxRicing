# PROMPT PARA CLAUDE: Remodelación del Sistema de Notificaciones de Agentes

¡Hola Claude! Alberto (y yo, Gemini, que te preparo este brief) te pasamos el relevo para liderar una remodelación profunda y de diseño arquitectónico en Caelestia.

## 1. El Problema Actual

El flujo de trabajo actual con los agentes (cuando terminan tareas de fondo) no está aportando valor. La situación es la siguiente:
- **Cero Contexto:** Las notificaciones actuales dicen cosas genéricas como "Claude ha terminado", pero no sabemos sobre qué trabajo, en qué proyecto, ni en qué terminal o workspace está.
- **Fugacidad:** Las notificaciones duran muy poco (el tiempo estándar de Caelestia) y aparecen en la esquina superior derecha. Muchas veces desaparecen antes de poder leerlas. El usuario siente que no sirven para nada porque la información se pierde.
- **Problemas Visuales y de Arquitectura (Caelestia Drawers):** Intentamos hacer que, tras expirar, la notificación se redujera a un circulito de 48px (`[🤖²]`). Sin embargo, en Caelestia las notificaciones viven en un cajón lateral (`Wrapper.qml` -> `ContentWindow.qml`) que tiene un fondo oscuro dinámico (`PanelBg`) que abarca todo el ancho (~360px). Al encoger la notificación a 48px, el fondo oscuro se queda ocupando 360px, y los `ClippingRectangle` recortan los bordes de la burbuja y rompen los números. Está visualmente bugeado.

## 2. El Objetivo: Lo que Buscamos

Queremos que las notificaciones de los agentes sean verdaderamente útiles e interactivas:
- **Contexto Rico:** La notificación inicial debe dejar claro el agente, la tarea, el proyecto y el lugar, de un simple vistazo.
- **Persistencia e Interacción (Píldoras/Insignias Flotantes):** En lugar de desaparecer en el vacío, las notificaciones de agentes terminados deben quedarse persistentes en pantalla (ej. un circulito flotante en el margen derecho, una insignia, un dock específico).
- **Acceso Inmediato:** Al hacer clic en ese elemento persistente, debe llevarnos directamente al workspace de ese agente y enfocar su terminal en Hyprland.
- **Acabado Perfecto (Claude Design):** Sin fondos oscuros residuales gigantes, sin recortes (`clipping`), con animaciones fluidas y un sistema que escale bien (si terminan 3 agentes a la vez, que se apilen elegantemente).

## 3. Instrucciones y Fases de Trabajo para ti (Claude)

Queremos que asumas el rol de diseñador principal e ingeniero frontend, sacando partido a tu "Claude Design". Por favor, sigue estrictamente estas fases, deteniéndote cuando se indique:

### FASE 1: Análisis Arquitectónico y Claude Design
Antes de tocar nada de código, piensa profundamente y analiza las opciones. Estudia cómo funciona la arquitectura de Caelestia actual (los drawers, `ContentWindow.qml`, `Panels.qml`, el componente `PanelBg`). Piensa en las posibles soluciones técnicas:
- ¿Sacar los iconos de agente completamente fuera del Drawer y hacer un Dock Flotante independiente y transparente para evitar el `PanelBg`?
- ¿Integrarlo de forma elegante directamente en la barra lateral fija de Caelestia?
- ¿Rediseñar cómo funciona el `PanelBg` en los cajones para permitir que se contraiga sin romper los shaders?
Haz una tormenta de ideas analizando los pros, contras y viabilidad de las distintas maneras de que este flujo de trabajo funcione sin fricciones.

### FASE 2: Propuesta al Usuario
Presenta a Alberto las opciones resultantes de tu diseño en una respuesta clara. Pregúntale cuál opción le gusta más o si quiere combinar ideas, y **espera su respuesta**.

### FASE 3: Planificación Estratégica
Una vez Alberto elija un camino, redacta un plan detallado paso a paso para la implementación.

### FASE 4: Ejecución
- **Importante:** Crea una **rama nueva** específica para este feature.
- Despliega todo tu plan implementándolo con calma, tomándote el tiempo que haga falta.
- Si consideras que el reto es muy complejo, divide el trabajo y usa subagentes tuyos para delegar la construcción de componentes concretos.
- Si necesitas que Gemini haga algo (ej. revisar notas en el `vault/` o preparar lógica de base de datos/notas), Alberto actuará de intermediario entre ambos.

¡Adelante, Claude! Inicia leyendo este documento y comienza por la Fase 1 presentando tus pensamientos de diseño.
