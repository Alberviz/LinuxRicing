pragma Singleton

import Quickshell

// Medidas compartidas entre el chasis, la lista y los hilos (en px lógicos).
Singleton {
    readonly property int cabecera: 46     // alto de la cabecera de cada panel
    readonly property int listaArriba: 6   // aire entre la cabecera y la primera fila
    readonly property int fila: 38         // alto de una fila de la lista
    readonly property int listaPie: 52     // pie de la lista (chips de ayuda)
    readonly property int margenContenido: 10
}
