package com.tecsys.gatewayplanner.rf.terrain;

/** Fonte de elevação do terreno. */
public interface TerrainProvider {

    /** Elevação em metros acima do nível do mar, ou {@link Double#NaN} se não houver dado. */
    double elevationM(double lat, double lon);

    /**
     * Elevação rápida (célula mais próxima, sem interpolação) para as amostras do meio do perfil,
     * onde uma diferença de poucos metros não muda o resultado e a velocidade importa
     * (milhões de consultas por estudo). Por padrão igual a {@link #elevationM}.
     */
    default double elevationFastM(double lat, double lon) {
        return elevationM(lat, lon);
    }
}
