package com.tecsys.gatewayplanner.rf.propagation;

import com.tecsys.gatewayplanner.rf.Geo;
import com.tecsys.gatewayplanner.rf.RadioParams;

/** Perda no espaço livre (Friis): só distância e frequência, sem relevo. */
public final class FreeSpaceModel implements PropagationModel {

    /** FSPL em dB, com f em MHz e d em km. */
    public static double fsplDb(double frequencyMhz, double distanceKm) {
        double d = Math.max(distanceKm, 0.001);
        return 32.44 + 20 * Math.log10(frequencyMhz) + 20 * Math.log10(d);
    }

    @Override
    public LinkResult evaluate(double txLat, double txLon, double rxLat, double rxLon, RadioParams p) {
        double d = Geo.distanceKm(txLat, txLon, rxLat, rxLon);
        return new LinkResult(fsplDb(p.frequencyMhz, d), d, false, 0);
    }
}
