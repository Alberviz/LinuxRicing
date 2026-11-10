from __future__ import annotations

from pathlib import Path
import tomllib
import pytest

from laura import rapido
from laura.tools import REGISTRY


def test_herramientas_existen_en_registry():
    # Obtener todas las tools que devuelven las reglas
    for _, fn in rapido._COMPILADAS:
        # Generar un match dummy o inspeccionar el código
        pass
    tools_usadas = {"control_musica", "volumen", "silenciar", "brillo", "hora_fecha", "bloquear_pantalla", "captura_pantalla"}
    for t in tools_usadas:
        assert t in REGISTRY, f"La herramienta {t} no está registrada en REGISTRY"


def test_positivos_y_negativos():
    # Positivos
    p1 = rapido.resolver("oye laura pon pausa a la música")
    assert p1 == rapido.Atajo("control_musica", {"accion": "reproducir_pausar"})

    p2 = rapido.resolver("sube el volumen un diez")
    assert p2 == rapido.Atajo("volumen", {"porcentaje": 10})

    p3 = rapido.resolver("baja el volumen un 20%")
    assert p3 == rapido.Atajo("volumen", {"porcentaje": -20})

    p4 = rapido.resolver("uf, esto suena muy alto, bájalo un 15")
    assert p4 == rapido.Atajo("volumen", {"porcentaje": -15})

    p5 = rapido.resolver("silencia el audio")
    assert p5 == rapido.Atajo("silenciar", {})

    p6 = rapido.resolver("qué hora es")
    assert p6 == rapido.Atajo("hora_fecha", {})

    p7 = rapido.resolver("bloquea la pantalla")
    assert p7 == rapido.Atajo("bloquear_pantalla", {})

    p8 = rapido.resolver("bloquea el ordenador que me voy a comer")
    assert p8 == rapido.Atajo("bloquear_pantalla", {})

    p9 = rapido.resolver("hazme una captura de pantalla")
    assert p9 == rapido.Atajo("captura_pantalla", {})

    p10 = rapido.resolver("saca un pantallazo")
    assert p10 == rapido.Atajo("captura_pantalla", {})

    # Negativos: deben dar None para no interferir con el LLM
    assert rapido.resolver("pausa y abre google") is None
    assert rapido.resolver("baja el volumen al 20") is None
    assert rapido.resolver("qué hora es en Tokio") is None
    assert rapido.resolver("ayer estuve con el volumen muy alto y me dolían los oídos") is None
    assert rapido.resolver("mi hermano abrió la puerta del garaje") is None
    assert rapido.resolver("cuéntame algo curioso sobre los pulpos") is None


def test_coherencia_con_examen():
    frases_path = Path(__file__).resolve().parents[1] / "eval" / "frases.toml"
    assert frases_path.exists()
    frases = tomllib.loads(frases_path.read_text())["frase"]

    capturas = 0
    for f in frases:
        txt = f["texto"]
        espera = f.get("espera", [])
        args_esp = f.get("args", [{}])
        at = rapido.resolver(txt)
        if at:
            capturas += 1
            assert espera and at.tool == espera[0], f"Tool incorrecta para '{txt}': {at.tool} vs {espera}"
            if args_esp and args_esp[0]:
                for k, v in args_esp[0].items():
                    assert at.args.get(k) == v, f"Arg {k} incorrecto para '{txt}': {at.args.get(k)} vs {v}"

    assert capturas >= 10, f"Se esperaban al menos 10 capturas de frases del examen, se obtuvieron {capturas}"


def test_decir():
    # hora_fecha con resultado ok
    at_hora = rapido.Atajo("hora_fecha")
    res_hora = {"ok": True, "hora": "18:30", "resumen": "Son las 18:30"}
    assert rapido.decir(at_hora, res_hora) == "Son las 18:30"

    # Otras herramientas ok devuelven vacío (solo overlay)
    at_vol = rapido.Atajo("volumen", {"porcentaje": 10})
    res_vol = {"ok": True, "resumen": "Volumen 40%"}
    assert rapido.decir(at_vol, res_vol) == ""

    at_mus = rapido.Atajo("control_musica", {"accion": "parar"})
    res_mus = {"ok": True, "resumen": "Música parada"}
    assert rapido.decir(at_mus, res_mus) == ""

    # Error
    res_err = {"ok": False, "error": "No hay ningún reproductor"}
    assert rapido.decir(at_mus, res_err) == "No he podido: No hay ningún reproductor."
