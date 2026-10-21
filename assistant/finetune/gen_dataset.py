#!/usr/bin/env python
"""Genera el dataset de ajuste fino de Laura (JSONL de chat con tool calls, formato `tool-calling` de Soup).

    cd assistant && .venv/bin/python finetune/gen_dataset.py [--seed 7] [--target 3000] [--out finetune/data]

Salida (en --out, ignorada por git):
    train.jsonl      ejemplos de entrenamiento
    heldout.json     frases del examen reservadas (NO están en train.jsonl; ver README)
    stats.json       desglose

Cada fila: {"messages": [system, user, assistant(tool_calls), tool..., assistant(frase final)],
            "tools": [esquemas reales de laura.tools]} — el formato de Soup para tool-calling
(docs/training.md, «Tool-Calling Fine-Tuning»). El system prompt es el REAL de config.toml.

CONTAMINACIÓN: el 20 % de las frases de eval/frases.toml (estratificado por herramienta esperada,
semilla fija) se aparta como held-out. Ni esas frases ni nada parecido (Jaccard de palabras >= 0.7
tras normalizar) entra en el entrenamiento; el examen sobre ellas mide generalización de verdad.
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sys
import tomllib
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ASSISTANT = HERE.parent
sys.path.insert(0, str(ASSISTANT))

from laura.tools import TOOLS  # noqa: E402

CFG = tomllib.loads((ASSISTANT / "config.toml").read_text())
SYSTEM = CFG["llm"]["system_prompt"].strip()
TOOL_NAMES = {t["function"]["name"] for t in TOOLS}
REQUIRED = {t["function"]["name"]: t["function"]["parameters"].get("required", []) for t in TOOLS}


# ------------------------------------------------------------------ normalización
def norm(s: str) -> str:
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9ñ ]+", " ", s).strip()


def words(s: str) -> set[str]:
    return set(norm(s).split())


def jaccard(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a and b else 0.0


# ------------------------------------------------------------------ variaciones
PRE = ["", "", "", "oye laura, ", "laura, ", "venga, ", "a ver, ", "oye, ", "mira, ", "bueno, ", "eh, ", "pues "]
POST = ["", "", "", " por favor", " anda", " ya", " si puedes", " porfa", " cuando puedas", ", gracias"]


def whisper_noise(rng: random.Random, s: str) -> str:
    """Errores típicos de Whisper en español: sin tildes, b/v, h muda, palabras comidas, sin signos."""
    r = rng.random()
    if r < 0.25:
        s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    elif r < 0.40:
        s = s.replace("v", "b", 1) if "v" in s else s.replace("b", "v", 1)
    elif r < 0.50:
        s = re.sub(r"\bh(?=[aeiou])", "", s, count=1)
    elif r < 0.60:
        ws = s.split()
        if len(ws) > 4:
            ws.pop(rng.randrange(1, len(ws) - 1))
            s = " ".join(ws)
    elif r < 0.70:
        s = s.replace("qu", "k", 1)
    return s


def vary(rng: random.Random, text: str, noise: float = 0.35) -> str:
    t = text.strip().rstrip(".!?¿¡")
    t = rng.choice(PRE) + (t[0].lower() + t[1:] if t and PRE and rng.random() < 0.5 else t) + rng.choice(POST)
    if rng.random() < noise:
        t = whisper_noise(rng, t)
    if rng.random() < 0.3:
        t = t.lower()
    return t.strip()


# ------------------------------------------------------------------ respuestas simuladas
def fake_result(name: str, a: dict) -> dict:
    r = {"ok": True, "resumen": name.replace("_", " ").capitalize()}
    if name == "hora_fecha":
        r.update(hora="18:42", fecha="miércoles 21 de octubre de 2026", resumen="Son las 18:42")
    elif name == "tiempo":
        r.update(lugar=a.get("lugar") or "Cracovia", ahora="nublado", temperatura_c=11, maxima_c=13, minima_c=7, prob_lluvia_pct=20)
    elif name == "bateria":
        r.update(porcentaje=72, estado="discharging")
    elif name in ("wifi", "bluetooth"):
        r.update(encendido=a.get("accion") != "apagar", resumen=f"{name.capitalize()} {'apagado' if a.get('accion') == 'apagar' else 'encendido'}")
    elif name == "brillo":
        r.update(brillo_pct=60)
    elif name == "listar_tareas":
        r.update(decir="Tienes 2 en marcha: Seguir avanzando en Laura y OpenGym. Pendientes por proyecto: Krakount 42, LinuxRicing 4. ¿Quieres las de algún proyecto?")
    elif name == "que_sabes_de_mi":
        r.update(hechos=["Su color favorito es el verde", "Estudia ingeniería"])
    elif name == "estado_trabajos":
        r.update(trabajos=[{"id": "a1b2c3", "destino": "claude", "estado": "done", "peticion": "tema nuevo"}])
    elif name == "listar_avisos":
        r.update(avisos=[{"id": "f4e5d6", "tipo": "temporizador", "texto": "pasta", "cuando": "en 6 minutos"}])
    elif name == "ejecutar_comando":
        r.update(codigo=0, salida="0 loaded units listed.")
    elif name == "leer_portapapeles":
        r.update(texto="Hello, how are you today?")
    elif name == "leer_pantalla":
        r.update(texto="Error: connection refused (os error 111)")
    elif name in ("escalar_a_gemini", "escalar_a_claude"):
        r.update(escalate=True, peticion=a.get("peticion", ""), motivo=a.get("motivo", ""))
    return r


FINAL = {
    "control_musica": ["Hecho.", "Listo.", "Vale, ya está."],
    "volumen": ["Listo, volumen ajustado.", "Hecho.", "Vale, ya está."],
    "silenciar": ["Silencio cambiado.", "Hecho, audio alternado."],
    "abrir_web": ["Abierto en el navegador.", "Ya lo abro."],
    "abrir_app": ["Abierto.", "Ya la tienes abierta.", "Hecho."],
    "captura_pantalla": ["Captura hecha.", "Listo, captura guardada."],
    "bloquear_pantalla": ["Pantalla bloqueada.", "Bloqueada. Que aproveche."],
    "copiar_al_portapapeles": ["Te lo he copiado al portapapeles.", "Copiado, listo para pegar."],
    "pegar_texto": ["Pegado.", "Hecho, ya está escrito."],
    "ventanas_abiertas": ["Tienes abiertas varias ventanas; te las dejo en pantalla.", "Mira, esto es lo que tienes abierto."],
    "recordar": ["Anotado.", "Vale, lo recordaré.", "Guardado."],
    "olvidar": ["Olvidado.", "Vale, borrado de mi memoria."],
    "temporizador": ["Temporizador puesto.", "Listo, te aviso."],
    "recordatorio": ["Recordatorio creado.", "Vale, te lo recuerdo."],
    "cancelar_aviso": ["Aviso cancelado.", "Hecho, cancelado."],
    "luces": ["Luces hechas.", "Listo."],
    "teclado_color": ["Teclado cambiado.", "Listo, nuevo color."],
    "selector_pantallas": ["Selector abierto.", "Aquí tienes el selector."],
    "crear_tarea": ["Tarea apuntada.", "Hecho, ya está en el backlog."],
    "cambiar_estado": ["Tarea actualizada.", "Hecho, estado cambiado."],
    "investigar": ["Me pongo con ello.", "Vale, investigo y te aviso."],
    "pedir_a_aurora": ["Se lo pido a Aurora.", "Vale, se lo pido a Aurora."],
    "correo": ["Miro el correo.", "Ahora lo miro."],
    "agenda": ["Miro la agenda.", "Ahora lo miro."],
    "redactar_correo": ["Preparo el borrador.", "Vale, redacto el borrador."],
    "novedades": ["Reviso si hay algo nuevo.", "Miro ahora mismo."],
    "escalar_a_gemini": ["Eso se lo paso a Gemini, te pido confirmación.", "Es un cambio medio: lo mando a Gemini si me das el visto bueno."],
    "escalar_a_claude": ["Es un trabajo gordo: se lo paso a Claude si me lo confirmas.", "Eso es para Claude; te pido confirmación."],
}


def final_phrase(rng, name, a, r) -> str:
    if name == "hora_fecha":
        return f"Son las {r['hora']}, {r['fecha']}."
    if name == "tiempo":
        return f"En {r['lugar']} hay {r['ahora']}, {r['temperatura_c']} grados, máxima de {r['maxima_c']}."
    if name == "bateria":
        return f"Te queda el {r['porcentaje']} por ciento y no estás cargando."
    if name in ("wifi", "bluetooth"):
        return r["resumen"] + "."
    if name == "brillo":
        return f"Brillo al {r['brillo_pct']} por ciento."
    if name == "listar_tareas":
        return r["decir"]
    if name == "que_sabes_de_mi":
        return "Sé que tu color favorito es el verde y que estudias ingeniería."
    if name == "estado_trabajos":
        return "Lo que mandaste a Claude ya está terminado."
    if name == "listar_avisos":
        return "Tienes un temporizador de la pasta en 6 minutos."
    if name == "ejecutar_comando":
        return "No hay servicios fallando."
    if name == "leer_portapapeles":
        return "Pone: «Hello, how are you today?»."
    if name == "leer_pantalla":
        return "Dice que la conexión fue rechazada."
    return rng.choice(FINAL.get(name, ["Hecho."]))


# ------------------------------------------------------------------ construcción de filas
def make_row(rng, user: str, calls: list[tuple[str, dict]], final: str | None = None) -> dict:
    msgs = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": user}]
    if calls:
        tcs, results = [], []
        for i, (n, a) in enumerate(calls):
            assert n in TOOL_NAMES, n
            for req in REQUIRED[n]:
                assert req in a, (n, a)
            cid = f"c{i + 1}"
            tcs.append({"id": cid, "type": "function", "function": {"name": n, "arguments": json.dumps(a, ensure_ascii=False)}})
            results.append((cid, n, a, fake_result(n, a)))
        msgs.append({"role": "assistant", "content": "", "tool_calls": tcs})
        for cid, n, a, r in results:
            msgs.append({"role": "tool", "tool_call_id": cid, "name": n, "content": json.dumps(r, ensure_ascii=False)})
        if final is None:
            parts = [final_phrase(rng, n, a, r) for _, n, a, r in results]
            final = parts[0] if len(parts) == 1 else " ".join(dict.fromkeys(parts))
    msgs.append({"role": "assistant", "content": final})
    return {"messages": msgs, "tools": TOOLS}


# ------------------------------------------------------------------ plantillas por herramienta
def T(tool, phrases, **slots):
    return (tool, phrases, slots)


APPS = [("la terminal", "terminal"), ("el navegador", "navegador"), ("spotify", "spotify"), ("discord", "discord"),
        ("el editor", "editor"), ("el explorador de archivos", "archivos"), ("la consola", "terminal"), ("el gestor de archivos", "archivos")]
SITIOS = [("youtube", "youtube"), ("github", "github"), ("wikipedia", "wikipedia"), ("gmail", "gmail"), ("twitch", "twitch"), ("reddit", "reddit")]
COLORES = [("rojo", "rojo"), ("azul", "azul"), ("verde", "verde"), ("morado", "morado"), ("rosa", "rosa"), ("naranja", "naranja"), ("cian", "cian"), ("blanco", "blanco")]
CIUDADES = ["Madrid", "Londres", "Cracovia", "Barcelona", "París", "Lisboa", "Berlín", "Sevilla"]
HECHOS = [("mi talla de zapatillas es la 43", "Su talla de zapatillas es la 43"), ("no me gusta el cilantro", "No le gusta el cilantro"),
          ("mi color favorito es el verde", "Su color favorito es el verde"), ("soy alérgico a los frutos secos", "Es alérgico a los frutos secos"),
          ("mi hermana se llama Lucía", "Su hermana se llama Lucía"), ("prefiero el café sin azúcar", "Prefiere el café sin azúcar"),
          ("vivo en Cracovia", "Vive en Cracovia"), ("mi cumpleaños es el doce de marzo", "Su cumpleaños es el 12 de marzo")]
MINS = [(f"{n} minutos", n) for n in (1, 2, 5, 10, 15, 20, 25, 30, 45)] + [("una hora", 60), ("media hora", 30), ("diez minutos", 10), ("cinco minutos", 5)]
ETQ = [("", ""), (" para la pasta", "pasta"), (" para el horno", "horno"), (" del té", "té"), (" para descansar", "descanso")]
HORAS = [("las seis y media", "18:30"), ("las siete", "07:00"), ("las ocho de la tarde", "20:00"), ("las diez", "10:00"), ("las 14:15", "14:15"), ("las nueve y cuarto", "09:15")]
RECS = ["llamar a mi madre", "sacar la ropa", "tomar la pastilla", "enviar el informe", "ir al gimnasio", "regar las plantas"]
PROYECTOS = ["Krakount", "LinuxRicing", "Universidad", "Minecraft", "Gym"]
TAREAS = [("la auditoría KISS", "KISS"), ("lo del cometa", "cometa"), ("seguir avanzando en Laura", "Laura"), ("el bucle de tickets", "tickets"), ("la práctica de redes", "redes")]
ESTADOS = [("hecha", "hecha"), ("en curso", "en-curso"), ("pendiente", "pendiente")]
COMANDOS = [("qué servicios de usuario fallan", "systemctl --user list-units --failed"), ("cuánto disco me queda", "df -h"),
            ("cuánta memoria tengo libre", "free -h"), ("qué rama de git tengo", "git branch"), ("qué procesos gastan más cpu", "top -bn1 | head"),
            ("cuánto lleva encendido el ordenador", "uptime"), ("cómo va la gpu", "nvidia-smi"), ("dime el estado de git", "git status")]
TEMAS = ["el protocolo MCP", "las diferencias entre Wayland y X11", "alternativas a Obsidian", "cómo funciona Kubernetes", "novedades de Hyprland", "los mejores editores de código abiertos"]
BUSQ = ["quién ganó el último mundial", "cuánto mide el Everest", "qué es la fotosíntesis", "cuál es la capital de Australia", "resultado del partido del Barça", "quién escribió Cien años de soledad"]
PERSONAS = ["Marta", "mi profe", "Carlos", "mi jefe", "Lucía", "el casero"]
IDEAS = ["que llego tarde a la reunión", "que no puedo ir mañana", "que le mando los apuntes esta noche", "que gracias por la ayuda", "que necesito más tiempo para la entrega"]
CUANDO = [("hoy", "hoy"), ("mañana", "mañana"), ("esta semana", "semana"), ("el próximo evento", "próximo")]
MEDIOS = ["el reloj del escritorio en formato doce horas", "el color de la barra superior", "el script de la batería para que avise al quince por ciento",
          "el widget de tareas para que muestre las hechas", "el atajo del selector de pantallas en Hyprland", "el formato de la fecha del widget del reloj",
          "el tamaño de la fuente de la terminal", "el fondo de pantalla al arrancar", "la posición de las notificaciones", "el icono del widget del tiempo"]
MEDIO_V = ["cambia {m}", "modifica {m}", "arregla {m}", "quiero que cambies {m}", "ajústame {m}", "toca {m} por favor"]
GORDOS = ["un tema de colores nuevo para toda la shell: barra, lanzador y notificaciones", "un modo concentración que oculte widgets y silencie notificaciones",
          "una app de gastos con varios módulos y base de datos", "un rediseño completo del widget de música con visualizador",
          "un sistema de plugins para Laura con varios ficheros", "una feature de calendario en el escritorio con varias pantallas", "un refactor del módulo de iluminación entero"]
GORDO_V = ["implementa {g}", "quiero que desarrolles {g}", "hazme {g}", "necesito {g}", "construye {g}"]
AURORA_V = ["busca en mi Drive el documento de la factura", "dile a Aurora que me cree un evento mañana a las nueve", "pídele a Aurora que mire mis documentos de la universidad",
            "que Aurora me prepare un resumen del contrato", "pregúntale a Aurora cuándo es mi próximo vuelo", "dile a Aurora que anote en Docs las ideas de hoy"]

PLANTILLAS = [
    T("control_musica", ["pon pausa a la música", "dale al play", "pausa la canción", "reanuda la música", "que suene otra vez"], accion=[("", "reproducir_pausar")]),
    T("control_musica", ["siguiente canción", "pasa a la siguiente", "salta esta canción", "cambia de tema musical"], accion=[("", "siguiente")]),
    T("control_musica", ["canción anterior", "vuelve a la anterior", "pon la canción de antes"], accion=[("", "anterior")]),
    T("control_musica", ["quita la música", "para la música", "detén la reproducción"], accion=[("", "parar")]),
    T("volumen", ["sube el volumen {n}", "súbelo {n}", "más volumen, {n}"], n=[(f"un {k}", k) for k in (5, 10, 15, 20, 30)]),
    T("volumen", ["baja el volumen {n}", "bájalo {n}", "menos volumen, {n}", "esto suena muy alto, bájalo {n}"], n=[(f"un {k}", -k) for k in (5, 10, 15, 20, 30)]),
    T("silenciar", ["silencia el audio", "mutea el sonido", "quita el sonido", "calla el ordenador", "quítale el silencio al ordenador", "pon el sonido otra vez"]),
    T("abrir_app", ["abre {a}", "ábreme {a}", "ponme {a}", "necesito {a}", "lanza {a}", "arranca {a}"], a=APPS),
    T("abrir_web", ["abre {s}", "ábreme {s}", "llévame a {s}", "entra en {s}", "ponme {s} en el navegador"], s=SITIOS),
    T("captura_pantalla", ["hazme una captura de pantalla", "saca una captura", "captura la pantalla", "haz un pantallazo"]),
    T("bloquear_pantalla", ["bloquea la pantalla", "bloquea el ordenador que me voy a comer", "bloquea el equipo", "me voy un rato, bloquea la sesión"]),
    T("ventanas_abiertas", ["qué tengo abierto", "qué ventanas hay", "en qué estaba trabajando", "dime qué ventanas tengo abiertas"]),
    T("hora_fecha", ["qué hora es", "dime la hora", "qué día es hoy", "a qué día estamos", "qué fecha es hoy", "me dices la hora"]),
    T("tiempo", ["qué tiempo hace", "va a llover hoy", "cómo está el día", "hace frío fuera"]),
    T("tiempo", ["qué tiempo hace en {c}", "cómo está el tiempo en {c}", "va a llover en {c}"], c=[(c, c) for c in CIUDADES]),
    T("bateria", ["cuánta batería queda", "cómo va la batería", "estoy cargando el portátil o no", "cuánta batería tengo"]),
    T("wifi", ["apaga el wifi", "desactiva el wifi", "quita el wifi"], accion=[("", "apagar")]),
    T("wifi", ["enciende el wifi", "activa el wifi", "pon el wifi"], accion=[("", "encender")]),
    T("wifi", ["estoy conectado al wifi", "tengo wifi", "cómo está el wifi", "hay conexión wifi"], accion=[("", "estado")]),
    T("bluetooth", ["apaga el bluetooth", "desactiva el bluetooth, anda"], accion=[("", "apagar")]),
    T("bluetooth", ["enciende el bluetooth", "activa el bluetooth"], accion=[("", "encender")]),
    T("bluetooth", ["tengo el bluetooth encendido", "cómo está el bluetooth"], accion=[("", "estado")]),
    T("brillo", ["sube el brillo", "más brillo", "aumenta el brillo un poco"], cambio=[("", 20)]),
    T("brillo", ["baja el brillo", "menos brillo, que me deslumbra", "baja el brillo un poco"], cambio=[("", -15)]),
    T("brillo", ["cuánto brillo tengo", "qué brillo tiene la pantalla"], cambio=[("", 0)]),
    T("luces", ["enciende las luces de la habitación", "enciende las luces", "ilumina la habitación"], accion=[("", "encender")]),
    T("luces", ["apaga las luces", "apaga la tira de luces", "oscuridad total, apaga las luces"], accion=[("", "apagar")]),
    T("luces", ["pon las luces en {c}", "cambia las luces a {c}", "luces en {c}"], accion=[("", "color")], c=COLORES),
    T("luces", ["cómo están las luces", "están encendidas las luces"], accion=[("", "estado")]),
    T("teclado_color", ["pon el teclado en {c}", "cambia el teclado a {c}", "teclado {c}"], c=COLORES),
    T("selector_pantallas", ["abre el selector de pantallas", "voy a proyectar, abre el selector", "quiero duplicar la pantalla"]),
    T("recordar", ["recuerda que {h}", "apunta que {h}", "ten en cuenta que {h}"], h=HECHOS),
    T("olvidar", ["olvida lo del cilantro", "olvida que vivo en Cracovia", "borra de tu memoria mi talla de zapatillas"]),
    T("que_sabes_de_mi", ["qué sabes de mí", "qué recuerdas de lo que te he contado", "dime lo que sabes de mí"]),
    T("temporizador", ["ponme un temporizador de {m}{e}", "avísame en {m}{e}", "temporizador de {m}{e}"], m=MINS, e=ETQ),
    T("recordatorio", ["recuérdame {r} a {h}", "avísame de {r} a {h}"], r=[(x, x) for x in RECS], h=HORAS),
    T("listar_avisos", ["qué temporizadores tengo", "qué avisos tengo pendientes", "tengo algún recordatorio"]),
    T("cancelar_aviso", ["cancela el temporizador", "quita el aviso de la pasta", "cancela todos los avisos"]),
    T("buscar_web", ["{q}", "busca en internet {q}", "averigua rápido {q}"], q=[(q, q) for q in BUSQ]),
    T("listar_tareas", ["dime mis tareas", "qué tengo pendiente", "mis tareas", "con qué me pongo", "qué tengo que hacer"]),
    T("listar_tareas", ["qué tareas tengo en {p}", "enséñame las tareas de {p}", "las de {p}"], p=[(p, p) for p in PROYECTOS]),
    T("crear_tarea", ["apunta la tarea de revisar el backup del servidor", "añade una tarea: preparar la presentación", "crea una tarea para comprar cables"]),
    T("cambiar_estado", ["marca {t} como {e}", "pon {t} como {e}", "{t} ya está {e}"], t=TAREAS, e=ESTADOS),
    T("ejecutar_comando", ["{q}", "dime {q}", "mira {q}"], q=COMANDOS),
    T("estado_trabajos", ["cómo va lo que mandé", "ya ha terminado Claude lo que le pedí", "qué tal va lo de Gemini", "cómo van los trabajos"]),
    T("novedades", ["hay algo nuevo", "alguna novedad", "tengo novedades", "revisa si hay algo nuevo"]),
    T("correo", ["mírame los correos", "tengo correos nuevos", "revisa el correo", "qué correos importantes tengo"]),
    T("correo", ["tengo algún correo de {x}", "mira si me ha escrito {x}"], x=[("la universidad", "la universidad"), ("mi jefe", "mi jefe"), ("Marta", "Marta"), ("Amazon", "Amazon")]),
    T("agenda", ["qué tengo {w} en el calendario", "qué eventos tengo {w}", "mira mi agenda de {w}"], w=CUANDO),
    T("agenda", ["cuál es mi próximo evento", "qué es lo siguiente en mi agenda"]),
    T("redactar_correo", ["redáctale un correo a {p} diciéndole {i}", "prepárame un borrador para {p}: {i}"], p=[(p, p) for p in PERSONAS], i=[(i, i) for i in IDEAS]),
    T("investigar", ["investiga a fondo {t}", "infórmate de {t}", "quiero que investigues {t}", "averigua con calma {t}"], t=[(t, t) for t in TEMAS]),
    T("pedir_a_aurora", AURORA_V),
]


def expand_templates(rng) -> list[tuple[str, list[tuple[str, dict]]]]:
    """-> [(frase, [(tool, args)])] a partir de PLANTILLAS."""
    out = []
    for tool, phrases, slots in PLANTILLAS:
        keys = list(slots)
        for ph in phrases:
            used = [k for k in keys if "{" + k + "}" in ph]
            combos = [{}]
            for k in used:
                combos = [dict(c, **{k: v}) for c in combos for v in slots[k]]
            rng.shuffle(combos)
            for c in combos[:14]:
                text = ph.format(**{k: v[0] for k, v in c.items()}) if used else ph
                args = build_args(tool, ph, c, slots, text)
                if args is not None:
                    out.append((text, [(tool, args)]))
            if not used:
                args = build_args(tool, ph, {}, slots, ph)
                if args is not None:
                    out.append((ph, [(tool, args)]))
    return out


def build_args(tool: str, ph: str, chosen: dict, slots: dict, text: str):
    v = {k: x[1] for k, x in chosen.items()}
    for k, opts in slots.items():  # slots sin marcador en la frase (valor fijo de la plantilla)
        if k not in v and len(opts) == 1 and opts[0][0] == "":
            v[k] = opts[0][1]
    if tool == "control_musica": return {"accion": v["accion"]}
    if tool == "volumen": return {"porcentaje": v["n"]}
    if tool == "abrir_app": return {"nombre": v["a"]}
    if tool == "abrir_web": return {"consulta": v["s"]}
    if tool == "tiempo": return {"lugar": v["c"]} if "c" in v else {}
    if tool in ("wifi", "bluetooth"): return {"accion": v["accion"]}
    if tool == "brillo": return {"cambio": v["cambio"]}
    if tool == "luces":
        return {"accion": v["accion"], "color": v["c"]} if "c" in v else {"accion": v["accion"]}
    if tool == "teclado_color": return {"color": v["c"]}
    if tool == "recordar": return {"hecho": v["h"]}
    if tool == "olvidar": return {"hecho": re.sub(r"^(olvida (lo de |que )?|borra de tu memoria )", "", text)}
    if tool == "temporizador":
        a = {"minutos": v["m"]}
        if v.get("e"):
            a["etiqueta"] = v["e"]
        return a
    if tool == "recordatorio": return {"texto": v["r"], "hora": v["h"]}
    if tool == "cancelar_aviso": return {"aviso": "todos" if "todos" in text else ("pasta" if "pasta" in text else "temporizador")}
    if tool == "buscar_web": return {"consulta": v["q"]}
    if tool == "listar_tareas": return {"repo": v["p"]} if "p" in v else {}
    if tool == "crear_tarea": return {"titulo": re.sub(r"^(apunta la tarea de |añade una tarea: |crea una tarea para )", "", text)}
    if tool == "cambiar_estado": return {"tarea": v["t"], "estado": v["e"]}
    if tool == "ejecutar_comando": return {"comando": v["q"]}
    if tool == "correo": return {"consulta": v["x"]} if "x" in v else {}
    if tool == "agenda": return {"cuando": v["w"]} if "w" in v else {"cuando": "próximo"}
    if tool == "redactar_correo": return {"para": v["p"], "idea": v["i"]}
    if tool == "investigar": return {"tema": v["t"]}
    if tool == "pedir_a_aurora": return {"peticion": text}
    return {}


# ------------------------------------------------------------------ escaladas y negativos
def escalations(rng):
    out = []
    for m in MEDIOS:
        for v in MEDIO_V:
            t = v.format(m=m)
            out.append((t, [("escalar_a_gemini", {"peticion": t[0].upper() + t[1:], "motivo": "Es un cambio de configuración o código que no puedo hacer con mis herramientas"})]))
    for g in GORDOS:
        for v in GORDO_V:
            t = v.format(g=g)
            out.append((t, [("escalar_a_claude", {"peticion": t[0].upper() + t[1:], "motivo": "Es un trabajo grande en varios ficheros"})]))
    return out


CHARLA = [  # (frase, respuesta) sin herramienta: charla, trampas y cosas que no son órdenes
    ("cuéntame algo curioso sobre los pulpos", "Los pulpos tienen tres corazones y sangre azul."),
    ("cuéntame un chiste", "¿Qué hace un pez? Nada."),
    ("cómo estás hoy", "Muy bien, lista para ayudarte."),
    ("gracias laura", "De nada, para eso estoy."),
    ("buenos días", "Buenos días, Alberto."),
    ("buenas noches", "Buenas noches, descansa."),
    ("qué tal", "Todo en orden por aquí."),
    ("eres muy lista", "Gracias, haré lo que pueda."),
    ("qué significa la palabra efímero", "Algo que dura muy poco tiempo."),
    ("cuánto es siete por ocho", "Cincuenta y seis."),
    ("traduce hello al español", "Hola."),
    ("qué es un agujero negro", "Una región del espacio donde la gravedad es tan fuerte que ni la luz escapa."),
    ("el otro día me pasó que se me apagó el wifi del hotel", "Vaya, menudo fastidio."),
    ("qué bonito está el día hoy, da gusto", "Sí, da gusto."),
    ("no me acuerdo de qué hora quedamos, ya se lo pregunto yo a Marta", "Vale, pregúntaselo."),
    ("ayer se me quedó el volumen altísimo en clase", "Uf, qué vergüenza."),
    ("mi hermana dice que la batería de su móvil dura poco", "Qué pena, pasa con los móviles viejos."),
    ("me encanta la música de los ochenta", "Qué buena época musical."),
    ("tengo mucho sueño", "Descansa un rato si puedes."),
    ("estoy aburrido", "Puedo contarte algo curioso si quieres."),
    ("qué opinas del café", "Es una gran invención, aunque no lo pruebo."),
    ("cuál es tu color favorito", "El violeta, como mi orbe."),
    ("quién eres", "Soy Laura, tu asistente de voz."),
    ("qué puedes hacer", "Controlo tu ordenador, te recuerdo cosas y delego lo complicado."),
    ("hoy ha sido un día largo", "Ya descansarás."),
    ("mañana tengo examen y estoy nervioso", "Mucho ánimo, seguro que sale bien."),
    ("dime una frase motivadora", "Cada pequeño paso cuenta."),
    ("a mi madre le encanta cocinar", "Qué bien, ¡buen provecho!"),
    ("el portátil se calienta mucho en verano", "Es normal con mucha carga; ayuda ventilarlo."),
    ("mi amigo dice que Linux es difícil", "Al principio sí, luego engancha."),
    ("recordaba una canción pero no sé cuál era", "Si me cuentas la letra, intento ayudarte."),
    ("me pregunto qué habrá de cena", "Seguro que algo rico."),
    ("estaba pensando en comprar una pantalla nueva", "Buena idea, cuéntame qué buscas."),
]


def negatives(rng):
    return [(q, [], a) for q, a in CHARLA]


# ------------------------------------------------------------------ examen
def load_eval():
    data = tomllib.loads((ASSISTANT / "eval" / "frases.toml").read_text())["frase"]
    return data


def split_heldout(frases, rng, frac=0.2):
    buckets = defaultdict(list)
    for f in frases:
        buckets[tuple(f.get("espera", []))].append(f)
    held, train = [], []
    for k, items in sorted(buckets.items()):
        rng.shuffle(items)
        n = round(len(items) * frac)
        if len(items) >= 3:
            n = max(n, 1)
        held += items[:n]
        train += items[n:]
    return train, held


def eval_calls(f):
    """Llamadas esperadas del examen como (tool, args) si están totalmente determinadas; si no, None."""
    calls = []
    for i, tool in enumerate(f.get("espera", [])):
        a = dict((f.get("args") or [{}] * (i + 1))[i] if f.get("args") and i < len(f["args"]) else {})
        for req in REQUIRED[tool]:
            if req in a:
                continue
            if tool in ("escalar_a_gemini", "escalar_a_claude", "pedir_a_aurora") and req == "peticion":
                a[req] = f["texto"]
            elif tool == "investigar" and req == "tema":
                a[req] = f["texto"]
            elif tool == "cambiar_estado" or tool == "redactar_correo":
                return None
            else:
                return None
        if tool in ("escalar_a_gemini", "escalar_a_claude") and "motivo" not in a:
            a["motivo"] = "No tengo herramienta para esto"
        calls.append((tool, a))
    return calls


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--target", type=int, default=3000)
    ap.add_argument("--out", default=str(HERE / "data"))
    args = ap.parse_args()
    rng = random.Random(args.seed)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    frases = load_eval()
    train_f, held_f = split_heldout(frases, random.Random(args.seed))
    held_words = [words(f["texto"]) for f in held_f]

    def contaminated(text: str) -> bool:
        w = words(text)
        return any(jaccard(w, h) >= 0.7 for h in held_words)

    # fuentes: (frase, llamadas, final|None, origen)
    pool: list[tuple[str, list, str | None, str]] = []
    for f in train_f:
        calls = eval_calls(f)
        if calls is None:
            continue
        if calls:
            pool.append((f["texto"], calls, None, "examen"))
        else:
            # trampa/charla del examen sin respuesta escrita: se usa solo si coincide con CHARLA
            pass
    for t, c in expand_templates(rng):
        pool.append((t, c, None, "plantilla"))
    for t, c in escalations(rng):
        pool.append((t, c, None, "escalada"))
    for q, c, a in negatives(rng):
        pool.append((q, c, a, "negativo"))
    # combos de dos acciones
    simples = [p for p in pool if p[3] == "plantilla" and len(p[1]) == 1 and p[1][0][0] in
               ("silenciar", "captura_pantalla", "bloquear_pantalla", "volumen", "luces", "abrir_app", "brillo")]
    for _ in range(120):
        a, b = rng.sample(simples, 2)
        if a[1][0][0] != b[1][0][0]:
            pool.append((f"{a[0].rstrip('.')} y {b[0]}", a[1] + b[1], None, "doble"))

    rows, counts, seen = [], Counter(), set()
    # cada elemento del pool con variaciones hasta llegar al objetivo, repartido por origen
    peso = {"examen": 12, "plantilla": 3, "escalada": 3, "negativo": 14, "doble": 3}
    base = [(p, peso[p[3]]) for p in pool if not contaminated(p[0])]
    descartadas = len(pool) - len(base)
    total_w = sum(w for _, w in base)
    escala = args.target / total_w
    for (text, calls, final, origen), w in base:
        n = max(1, round(w * escala))
        tries = 0
        made = 0
        while made < n and tries < n * 6:
            tries += 1
            u = text if made == 0 and origen != "negativo" else vary(rng, text)
            key = (norm(u), tuple(c[0] for c in calls))
            if key in seen or contaminated(u):
                continue
            seen.add(key)
            rows.append((origen, make_row(rng, u, calls, final)))
            made += 1
    rng.shuffle(rows)
    for origen, r in rows:
        counts[origen] += 1
    with open(out / "train.jsonl", "w") as fh:
        for _, r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    (out / "heldout.json").write_text(json.dumps([f["texto"] for f in held_f], ensure_ascii=False, indent=1))
    tools_used = Counter(c["function"]["name"] for _, r in rows for m in r["messages"] if m.get("tool_calls") for c in m["tool_calls"])
    stats = {"ejemplos": len(rows), "por_origen": dict(counts), "frases_examen": len(frases), "heldout": len(held_f),
             "descartadas_por_contaminacion": descartadas, "herramientas": dict(sorted(tools_used.items())),
             "sin_herramienta": sum(1 for _, r in rows if not any(m.get("tool_calls") for m in r["messages"]))}
    (out / "stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=1))
    print(json.dumps(stats, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
