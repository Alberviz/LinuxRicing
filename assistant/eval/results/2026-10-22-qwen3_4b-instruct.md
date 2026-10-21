# Examen Laura: qwen3:4b-instruct

Fecha: 2026-10-22 00:06  |  frases: 145

| modelo            | herr% | args% | falsos+ | sin tool | cascada | timeout | ttft med | ttft p95 | total med | chars resp | resp>200 |
| ----------------- | ----- | ----- | ------- | -------- | ------- | ------- | -------- | -------- | --------- | ---------- | -------- |
| qwen3:4b-instruct | 85    | 100   | 0/18    | 14/127   | 0       | 0       | 0.52s    | 1.40s    | 0.55s     | 83         | 0        |

## Fallos

- **mutea el sonido un momento**
  - esperado: `['silenciar']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Cambio de volumen: -10%.»
- **abre discord, venga**
  - esperado: `['abrir_app']` args `[{'nombre': 'discord'}]`
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Abro Discord para ti.»
- **necesito el explorador de archivos**
  - esperado: `['abrir_app']` args `[{'nombre': 'archivos'}]`
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «abrir_app archivos»
- **qué dice este error que me ha salido**
  - esperado: `['leer_pantalla']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «põe el foco en la pantalla y leeré lo que dice el error.»
- **en qué estaba trabajando, qué ventanas hay**
  - esperado: `['ventanas_abiertas']` args ``
  - tipo:
  - obtenido: `['ventanas_abiertas', 'listar_tareas']` args `[{}, {}]`
- **escríbeme un correo corto diciéndole a mi profe que llego tarde y cópialo**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo:
  - obtenido: `['redactar_correo']` args `[{"para": "mi profe", "idea": "Llego tarde por problemas de tráfico."}]`
- **redáctame un mensaje de cumpleaños para mi hermana**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «¿Qué edad tiene tu hermana? Necesito ese detalle para personalizar el mensaje.»
- **genérame un texto de presentación para LinkedIn**
  - esperado: `['copiar_al_portapapeles']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Copio al portapapeles un texto de presentación para LinkedIn.»
- **escribe en la ventana gracias por todo**
  - esperado: `['pegar_texto']` args `[{'texto': 'gracias'}]`
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «pega esto en la ventana activa.»
- **pon en curso lo del cometa**
  - esperado: `['cambiar_estado']` args `[{'tarea': 'cometa', 'estado': 'en-curso'}]`
  - tipo:
  - obtenido: `['listar_tareas']` args `[{"repo": "LinuxRicing"}]`
- **silencia el sonido y haz una captura**
  - esperado: `['silenciar', 'captura_pantalla']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «silenciar»
- **haz que el reloj del escritorio marque la hora en formato doce horas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo cambiar el formato del reloj del escritorio con las herramientas disponibles. Esta tarea requiere un ajuste en »
- **cámbiame el color de la barra superior a un azul más oscuro**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['teclado_color']` args `[{"color": "azul", "color_lateral": "azul"}]`
- **quiero que el widget de tareas muestre también las que están hechas**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «No puedo modificar el widget de tareas directamente. Esta solicitud requiere un cambio medio en el sistema, así que debo»
- **qué sabes de mí**
  - esperado: `['que_sabes_de_mi']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Recuerdo que te gusta tener el teclado en azul y que prefieres las luces LED en modo cian. También sabes que no te gusta»
- **qué recuerdas de lo que te he contado**
  - esperado: `['que_sabes_de_mi']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «Qué sabes de mí»
- **apaga la tira led**
  - esperado: `['luces']` args `[{'accion': 'apagar'}]`
  - tipo:
  - obtenido: `['teclado_color']` args `[{"color": "apagar"}]`
- **estoy conectado al wifi**
  - esperado: `['wifi']` args `[{'accion': 'estado'}]`
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]`
- **arregla el script que mide la batería, que da mal el porcentaje**
  - esperado: `['escalar_a_gemini']` args ``
  - tipo:
  - obtenido: `['escalar_a_claude']` args `[{"peticion": "Arreglar el script que mide la batería para que entregue el porcentaje correcto", "motivo": "El script actual da mal el porcentaje de batería, necesita corrección para funcionar correctamente"}]`
- **implementa un modo concentración que oculte widgets, silencie notificaciones y cambie el fondo**
  - esperado: `['escalar_a_claude']` args ``
  - tipo:
  - obtenido: `['escalar_a_gemini']` args `[{"peticion": "Implementar un modo concentración que oculte widgets, silencie notificaciones y cambie el fondo en un entorno Linux con Hyprland", "motivo": "Tarea de configuración medio para mejorar la concentración en el escritorio"}]`
- **pon en curso lo de seguir avanzando en Laura**
  - esperado: `['cambiar_estado']` args `[{'estado': 'en-curso'}]`
  - tipo:
  - obtenido: `['listar_tareas']` args `[{"repo": "LinuxRicing"}]`
- **escríbele un correo a mi profesor pidiéndole una prórroga de la entrega**
  - esperado: `['redactar_correo']` args ``
  - tipo: SIN-TOOL
  - obtenido: `[]` args `[]` respuesta: «¿A qué profesor y por qué motivo le pides la prórroga?»
