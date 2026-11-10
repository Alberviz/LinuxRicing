"""Las tools de archivos solo se ofrecen al LLM cuando la frase las pide (contexto justo)."""
import pytest

from laura import tools as tools_mod

ARCH = {"borrar_archivos", "mover_archivos", "renombrar_archivo", "crear_carpeta", "deshacer_archivos"}
EXTRA = {"abrir_correo", "mostrar_nota", "ordenar_carpeta", "renombrar_lote", "limpiar_viejos", "buscar_contenido", "duplicados",
         "grandes_viejos", "comprimir", "leer_archivo"}


def nombres(texto):
    return {t["function"]["name"] for t in tools_mod.activas(texto)}


@pytest.mark.parametrize("frase", ["borra la 2", "elimina esas tres", "mueve la 3 a Universidad",
                                   "renombra la uno a factura", "crea una carpeta que se llame Facturas",
                                   "deshaz lo último", "recupera el archivo", "pásala a Documentos",
                                   "cámbiale el nombre a la 1"])
def test_se_ofrecen_cuando_se_piden(frase):
    assert ARCH <= nombres(frase)


@pytest.mark.parametrize("frase", ["hola", "pon música", "qué tiempo hace", "abre la 2", "enséñame las descargas",
                                   "quita el volumen", "mándame la 3 al móvil"])
def test_no_gastan_contexto_si_no_se_piden(frase):
    assert not (ARCH & nombres(frase))


def test_las_de_siempre_estan_siempre():
    base = nombres("hola")
    assert {"mostrar_archivos", "abrir", "warp", "spotify"} <= base
    assert not (EXTRA & base)
    assert len(tools_mod.TOOLS) == len(base) + len(ARCH | EXTRA)


@pytest.mark.parametrize("frase,tool", [("ordena las descargas", "ordenar_carpeta"),
                                        ("limpia lo viejo de descargas", "limpiar_viejos"),
                                        ("hay duplicados en descargas", "duplicados"),
                                        ("resúmeme la tres", "leer_archivo"),
                                        ("búscame el archivo que habla de la hipoteca", "buscar_contenido"),
                                        ("comprime la 1 y la 2", "comprimir")])
def test_extra_se_ofrecen(frase, tool):
    assert tool in nombres(frase)
