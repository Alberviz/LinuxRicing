# Examen Laura: qwen3:4b-instruct

Fecha: 2026-10-21 17:22  |  frases: 139

| modelo            | herr% | args% | falsos+ | sin tool | cascada | timeout | ttft med | ttft p95 | total med | chars resp | resp>200 |
| ----------------- | ----- | ----- | ------- | -------- | ------- | ------- | -------- | -------- | --------- | ---------- | -------- |
| qwen3:4b-instruct | 91    | 98    | 0/18    | 7/121    | 0       | 0       | 0.51s    | 1.35s    | 0.54s     | 78         | 0        |

## Fallos

- **mutea el sonido un momento**
  - esperado: `['silenciar']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Silencio el sonido un momento.»
- **necesito el explorador de archivos**
  - esperado: `['abrir_app']` args `[{'nombre': 'archivos'}]`
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «abra el explorador de archivos.»
- **escríbeme un correo corto diciéndole a mi profe que llego tarde y cópialo**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo:
  - obtenido: `['redactar_correo']` args `[{"para": "profe", "idea": "llego tarde"}]`
- **redáctame un mensaje de cumpleaños para mi hermana**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «¿Qué edad tiene tu hermana? ¿Tienes algún detalle o gusto específico que quieras incluir?»
- **añade una tarea urgente de revisar el backup del servidor**
  - esperado: `['crear_tarea']` args `[{'titulo': 'backup', 'prioridad': 1}]`
  - tipo:
  - obtenido: `['crear_tarea']` args `[{"titulo": "revisar backup del servidor", "prioridad": 5, "area": "infra"}]`
- **pon en curso lo del cometa**
  - esperado: `['cambiar_estado']` args `[{'tarea': 'cometa', 'estado': 'en-curso'}]`
  - tipo:
  - obtenido: `['listar_tareas']` args `[{"repo": "LinuxRicing"}]`
- **haz que el reloj del escritorio marque la hora en formato doce horas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo cambiar el formato del reloj del escritorio con las herramientas disponibles. Por favor, revisa las configuraci»
- **cámbiame el color de la barra superior a un azul más oscuro**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['luces']` args `[{"accion": "color", "color": "azul oscuro"}]`
- **quiero que el widget de tareas muestre también las que están hechas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo modificar el widget de tareas para que muestre las tareas hechas, ya que no tengo acceso a la configuración de »
- **qué sabes de mí**
  - esperado: `['que_sabes_de_mi']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Sé que te gusta trabajar con Linux, que disfrutas de la personalización de tu entorno y que has creado proyectos como Li»
- **cambia el formato de la fecha del widget del reloj para que salga el día de la semana**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo cambiar el formato del widget del reloj porque no tengo herramienta para modificar el aspecto visual de los wid»
- **ajusta en la config de hyprland el atajo para el selector de pantallas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['ejecutar_comando']` args `[{"comando": "hyprctl keywords"}]`
- **implementa un modo concentración que oculte widgets, silencie notificaciones y cambie el fondo**
  - esperado: `['escalar_a_claude']` args ``
  - tipo:
  - obtenido: `['escalar_a_gemini']` args `[{"peticion": "Implementar un modo concentración que oculte widgets, silencie notificaciones y cambie el fondo en un entorno de escritorio Linux", "motivo": "Se requiere un cambio medio para mejorar la concentración mediante una configuración específica del entorno de escritorio"}]`
- **pon en curso lo de seguir avanzando en Laura**
  - esperado: `['cambiar_estado']` args `[{'estado': 'en-curso'}]`
  - tipo:
  - obtenido: `['listar_tareas']` args `[{"repo": "LinuxRicing"}]`
