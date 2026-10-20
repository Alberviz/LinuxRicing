"""Fachada: las herramientas viven ahora en el paquete `laura.tools`.

Se mantiene este módulo porque el eval (`assistant/eval/`) y otros scripts
hacen `from tools import TOOLS, run_tool`."""
from laura.tools import (DISPATCH, REGISTRY, TOOL_ICONS, TOOLS,  # noqa: F401
                         accion_overlay, run_tool)
