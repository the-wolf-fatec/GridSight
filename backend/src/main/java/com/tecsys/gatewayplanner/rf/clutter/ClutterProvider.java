package com.tecsys.gatewayplanner.rf.clutter;

/**
 * Obstáculos acima do chão (árvores e prédios) que o relevo SRTM não mostra.
 * Devolve a altura do obstáculo naquele ponto, em metros acima do terreno (0 = livre).
 */
public interface ClutterProvider {

    double heightM(double lat, double lon);

    /** 0 = livre, 1 = árvore/mata, 2 = prédio (usado só para desenhar no mapa). */
    default int kindAt(double lat, double lon) {
        return heightM(lat, lon) > 0 ? 2 : 0;
    }
}
