package com.tecsys.gatewayplanner.rf.terrain;

/** Terreno plano a 0 m. Útil para testes e como comparação "sem relevo". */
public final class FlatTerrain implements TerrainProvider {
    @Override
    public double elevationM(double lat, double lon) {
        return 0;
    }
}
