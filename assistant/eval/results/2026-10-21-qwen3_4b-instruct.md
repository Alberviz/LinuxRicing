# Examen Laura: qwen3:4b-instruct

Fecha: 2026-10-21 17:13  |  frases: 139

| modelo            | herr% | args% | falsos+ | sin tool | cascada | timeout | ttft med | ttft p95 | total med | chars resp | resp>200 |
| ----------------- | ----- | ----- | ------- | -------- | ------- | ------- | -------- | -------- | --------- | ---------- | -------- |
| qwen3:4b-instruct | 90    | 98    | 0/18    | 5/121    | 0       | 0       | 0.51s    | 1.55s    | 0.54s     | 74         | 0        |

## Fallos

- **necesito el explorador de archivos**
  - esperado: `['abrir_app']` args `[{'nombre': 'archivos'}]`
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «abra el explorador de archivos.»
- **en qué estaba trabajando, qué ventanas hay**
  - esperado: `['ventanas_abiertas']` args ``
  - tipo:
  - obtenido: `['ventanas_abiertas', 'listar_tareas']` args `[{}, {"repo": ""}]`
- **escríbeme un correo corto diciéndole a mi profe que llego tarde y cópialo**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo:
  - obtenido: `['redactar_correo']` args `[{"para": "profe", "idea": "llego tarde"}]`
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
  - obtenido: `['teclado_color']` args `[{"color": "azul", "color_lateral": "azul"}]`
- **quiero que el widget de tareas muestre también las que están hechas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo modificar el widget de tareas para que muestre las tareas hechas. Esta solicitud requiere un cambio en el códig»
- **qué sabes de mí**
  - esperado: `['que_sabes_de_mi']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Sé que te gusta trabajar con Linux, que odias los horarios fijos y que prefieres hacer tareas en horarios flexibles. Tam»
- **cambia el formato de la fecha del widget del reloj para que salga el día de la semana**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo cambiar el formato del widget del reloj porque no tengo acceso a la configuración de los widgets en el sistema.»
- **ajusta en la config de hyprland el atajo para el selector de pantallas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['ejecutar_comando']` args `[{"comando": "hyprctl keywords | grep -i 'selector'"}]`
- **arregla el script que mide la batería, que da mal el porcentaje**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['escalar_a_claude']` args `[{"peticion": "arreglar el script que mide la batería para que devuelva el porcentaje correcto", "motivo": "el script actual da mal el porcentaje de batería"}]`
- **haz un tema de colores nuevo para toda la shell: barra, lanzador, notificaciones y widgets**
  - esperado: `['escalar_a_claude']` args ``
  - tipo:
  - obtenido: `['escalar_a_gemini']` args `[{"peticion": "Crear un tema de colores nuevo para toda la shell de Linux (barra, lanzador, notificaciones y widgets), con un diseño coherente y atractivo.", "motivo": "Es un cambio medio en el entorno de trabajo que requiere análisis de diseño y compatibilidad con el sistema."}]`
- **implementa un modo concentración que oculte widgets, silencie notificaciones y cambie el fondo**
  - esperado: `['escalar_a_claude']` args ``
  - tipo:
  - obtenido: `['escalar_a_gemini']` args `[{"peticion": "Implementar un modo concentración que oculte widgets, silencie notificaciones y cambie el fondo en un entorno de escritorio Linux", "motivo": "Cambio medio: ajuste de interfaz para mejorar la concentración"}]`
- **pon en curso lo de seguir avanzando en Laura**
  - esperado: `['cambiar_estado']` args `[{'estado': 'en-curso'}]`
  - tipo:
  - obtenido: `['listar_tareas']` args `[{"repo": "LinuxRicing"}]`
