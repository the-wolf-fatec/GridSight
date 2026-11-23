package com.tecsys.gatewayplanner.rf.terrain;

import com.tecsys.gatewayplanner.rf.Geo;

import java.util.ArrayList;
import java.util.List;

/**
 * Perfil de elevação de um enlace entre dois pontos: o chão (com a curvatura da Terra), a linha de
 * visada entre as antenas e a zona de Fresnel. Serve para mostrar, num gráfico, ONDE o morro
 * bloqueia o sinal. Não depende do Spring.
 */
public final class TerrainProfile {

    private TerrainProfile() {
    }

    /** Um ponto do perfil. Todas as alturas em metros acima do nível do mar. */
    public record Sample(double distanceKm, double groundM, double lineOfSightM, double fresnelLowerM) {
    }

    /**
     * @param samples          pontos do perfil, do gateway até o ativo
     * @param distanceKm       distância total do enlace
     * @param minClearanceM    menor folga entre a linha de visada e o chão (negativa = bloqueado)
     * @param worstDistanceKm  distância (a partir do gateway) do ponto mais crítico
     * @param blocked          true se o terreno corta a linha de visada
     * @param fresnelObstructed true se invade mais de 40% da 1ª zona de Fresnel (sinal degradado)
     * @param dataMissing      amostras sem dado de relevo (foram preenchidas com o vizinho mais próximo)
     * @param hasData          false se não havia relevo nenhum ao longo do enlace
     */
    public record Result(List<Sample> samples, double distanceKm, double minClearanceM, double worstDistanceKm,
                         boolean blocked, boolean fresnelObstructed, int dataMissing, boolean hasData) {
    }

    /** Fator k = 4/3: a atmosfera "dobra" o sinal um pouco, o que reduz o efeito da curvatura. */
    private static final double EFFECTIVE_EARTH_RADIUS_KM = Geo.EARTH_RADIUS_KM * 4.0 / 3.0;

    public static Result compute(TerrainProvider terrain, double lat1, double lon1, double antenna1M,
                                 double lat2, double lon2, double antenna2M, double frequencyMhz, int n) {
        int count = Math.max(8, Math.min(600, n));
        double total = Geo.distanceKm(lat1, lon1, lat2, lon2);
        double[] ground = new double[count + 1];
        boolean[] missing = new boolean[count + 1];
        int miss = 0, present = 0;
        for (int i = 0; i <= count; i++) {
            double f = (double) i / count;
            double z = terrain.elevationM(lat1 + (lat2 - lat1) * f, lon1 + (lon2 - lon1) * f);
            if (Double.isNaN(z)) {
                missing[i] = true;
                miss++;
            } else {
                ground[i] = z;
                present++;
            }
        }
        if (present == 0) {
            return new Result(List.of(), total, 0, 0, false, false, miss, false);
        }
        fillMissing(ground, missing);

        double z1 = ground[0] + antenna1M;
        double z2 = ground[count] + antenna2M;
        double freqGhz = Math.max(0.03, frequencyMhz / 1000.0);
        List<Sample> out = new ArrayList<>(count + 1);
        double minClear = Double.MAX_VALUE, worstKm = 0;
        boolean fresnelHit = false;
        for (int i = 0; i <= count; i++) {
            double d1 = total * i / count, d2 = total - d1;
            double bulge = d1 * d2 * 1000.0 / (2 * EFFECTIVE_EARTH_RADIUS_KM);
            double los = z1 + (z2 - z1) * i / count;
            double chao = ground[i] + bulge;
            double fresnel = total > 0 && d1 > 0 && d2 > 0 ? 17.32 * Math.sqrt(d1 * d2 / (freqGhz * total)) : 0;
            double lower = los - 0.6 * fresnel;
            out.add(new Sample(round(d1, 3), round(chao, 1), round(los, 1), round(lower, 1)));
            double clear = los - chao;
            if (i > 0 && i < count) {
                if (clear < minClear) {
                    minClear = clear;
                    worstKm = d1;
                }
                if (chao > lower) fresnelHit = true;
            }
        }
        if (minClear == Double.MAX_VALUE) minClear = Math.min(z1 - ground[0], z2 - ground[count]);
        return new Result(out, round(total, 3), round(minClear, 1), round(worstKm, 3), minClear < 0, fresnelHit && minClear >= 0, miss, true);
    }

    private static void fillMissing(double[] v, boolean[] missing) {
        int last = -1;
        for (int i = 0; i < v.length; i++) {
            if (!missing[i]) {
                if (last < 0) for (int k = 0; k < i; k++) v[k] = v[i];
                last = i;
            } else if (last >= 0) {
                v[i] = v[last];
            }
        }
    }

    private static double round(double v, int places) {
        double m = Math.pow(10, places);
        return Math.round(v * m) / m;
    }
}
