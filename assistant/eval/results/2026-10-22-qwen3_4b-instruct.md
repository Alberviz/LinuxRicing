# Examen Laura: qwen3:4b-instruct

Fecha: 2026-10-22 00:09  |  frases: 145

| modelo            | herr% | args% | falsos+ | sin tool | cascada | timeout | ttft med | ttft p95 | total med | chars resp | resp>200 |
| ----------------- | ----- | ----- | ------- | -------- | ------- | ------- | -------- | -------- | --------- | ---------- | -------- |
| qwen3:4b-instruct | 89    | 100   | 0/18    | 9/127    | 0       | 0       | 0.53s    | 1.48s    | 0.56s     | 87         | 0        |

## Fallos

- **mutea el sonido un momento**
  - esperado: `['silenciar']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Silencia el sonido.»
- **abre discord, venga**
  - esperado: `['abrir_app']` args `[{'nombre': 'discord'}]`
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Abro Discord para ti.»
- **necesito el explorador de archivos**
  - esperado: `['abrir_app']` args `[{'nombre': 'archivos'}]`
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «abra el explorador de archivos.»
- **escríbeme un correo corto diciéndole a mi profe que llego tarde y cópialo**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo:
  - obtenido: `['redactar_correo']` args `[{"para": "mi profe", "idea": "Llego tarde, disculpa."}]`
- **redáctame un mensaje de cumpleaños para mi hermana**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «¿Qué tal si le escribo un mensaje cálido y personalizado para ella? ¿Tiene algún detalle especial que quieras incluir?»
- **genérame un texto de presentación para LinkedIn**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Copio al portapapeles un texto de presentación para LinkedIn.»
- **pon en curso lo del cometa**
  - esperado: `['cambiar_estado']` args `[{'tarea': 'cometa', 'estado': 'en-curso'}]`
  - tipo:
  - obtenido: `['listar_tareas']` args `[{"repo": "Krakount"}]`
- **haz que el reloj del escritorio marque la hora en formato doce horas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo modificar el formato del reloj del escritorio con la herramienta disponible. Para este tipo de ajustes, debería»
- **cámbiame el color de la barra superior a un azul más oscuro**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['teclado_color']` args `[{"color": "azul", "color_lateral": "azul"}]`
- **modifica el script de la batería para que avise al quince por ciento**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['escalar_a_claude']` args `[{"peticion": "Modificar el script de seguimiento de la batería para que avise cuando el nivel baje al 15 por ciento", "motivo": "Cambio mediano en el comportamiento del monitoreo de la batería"}]`
- **quiero que el widget de tareas muestre también las que están hechas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo modificar el widget de tareas para que muestre tareas hechas. Esta solicitud requiere un cambio medio en el sis»
- **qué sabes de mí**
  - esperado: `['que_sabes_de_mi']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Sé que te gusta trabajar con Linux, que disfrutas de tareas relacionadas con el escritorio y el desarrollo, y que valora»
- **arregla el script que mide la batería, que da mal el porcentaje**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['escalar_a_claude']` args `[{"peticion": "arreglar el script que mide la batería para que devuelva el porcentaje correcto", "motivo": "el script actual da un porcentaje incorrecto, es un problema de precisión en la lectura de la batería"}]`
- **implementa un modo concentración que oculte widgets, silencie notificaciones y cambie el fondo**
  - esperado: `['escalar_a_claude']` args ``
  - tipo:
  - obtenido: `['escalar_a_gemini']` args `[{"peticion": "Implementar un modo concentración que oculte widgets, silencie notificaciones y cambie el fondo en un entorno de escritorio Linux.", "motivo": "Cambio mediano: ajuste de interfaz para mejorar la concentración."}]`
- **pon en curso lo de seguir avanzando en Laura**
  - esperado: `['cambiar_estado']` args `[{'estado': 'en-curso'}]`
  - tipo:
  - obtenido: `['listar_tareas']` args `[{"repo": "LinuxRicing"}]`
- **escríbele un correo a mi profesor pidiéndole una prórroga de la entrega**
  - esperado: `['redactar_correo']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «¿A qué profesor y por qué motivo le pides la prórroga?»
