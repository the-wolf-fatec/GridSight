package com.tecsys.gatewayplanner.rf.propagation;

/**
 * Resultado do cálculo de um enlace.
 *
 * @param pathLossDb        perda total de propagação (espaço livre + difração)
 * @param distanceKm        distância gateway -> dispositivo
 * @param terrainMissing    true se faltou dado de relevo e o cálculo caiu para espaço livre
 * @param diffractionLossDb parte da perda causada pelo relevo (0 = linha de visada livre)
 */
public record LinkResult(double pathLossDb, double distanceKm, boolean terrainMissing, double diffractionLossDb) {
}
