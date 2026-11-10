pragma Singleton

import QtQuick
import Quickshell

// Medidas y sistema de movimiento compartidos por todo el holograma (px lógicos, ms).
Singleton {
    readonly property int cabecera: 46     // alto de la cabecera de cada panel
    readonly property int listaArriba: 6   // aire entre la cabecera y la primera fila
    readonly property int fila: 38         // alto de una fila de la lista
    readonly property int listaPie: 52     // pie de la lista (chips de ayuda)
    readonly property int margenContenido: 10

    // ---------------------------------------------------------------- tiempos
    // Regla: lo que responde a la mano es corto; lo que viaja por la pantalla, más largo;
    // las salidas siempre algo más rápidas que su entrada. Nada pasa de ~0,6 s salvo el
    // barrido decorativo, que no bloquea nada.
    readonly property int tMicro: 110      // hover, pulsar: respuesta inmediata
    readonly property int tRapido: 180     // fundidos de indicadores, retraer un hilo
    readonly property int tMedio: 280      // cambios de estado, página, fila que entra
    readonly property int tLento: 420      // dibujar un hilo, fila que se va
    readonly property int tVuelo: 520      // panel que vuela desde la píldora
    readonly property int tSalida: 330     // panel que vuelve a la píldora
    readonly property int tBarrido: 620    // línea de luz que recorre un panel al llegar

    // Escalonados (cascadas)
    readonly property int escalonPanel: 85 // paneles que nacen en el mismo instante
    readonly property int escalonSalida: 55
    readonly property int escalonFila: 26  // filas de la lista / del panel de confirmar
    readonly property int maxEscalon: 340  // tope para que una cascada larga no se haga eterna

    // ---------------------------------------------------------------- curvas
    readonly property int curvaEntra: Easing.OutCubic   // algo llega: frena al final
    readonly property int curvaSale: Easing.InCubic     // algo se va: acelera al irse
    readonly property int curvaCambia: Easing.InOutCubic // algo cambia en su sitio
    readonly property int curvaFundido: Easing.OutQuad   // opacidades
}
