package com.tecsys.gatewayplanner.rf;

import com.tecsys.gatewayplanner.rf.propagation.FreeSpaceModel;
import com.tecsys.gatewayplanner.rf.propagation.LinkResult;
import com.tecsys.gatewayplanner.rf.propagation.PropagationModel;

import java.util.Arrays;
import java.util.List;
import java.util.concurrent.atomic.LongAdder;
import java.util.stream.IntStream;

/**
 * Monta a {@link CoverageMatrix}. Para não avaliar todos os pares:
 *  1. só olha ativos dentro de {@code maxRangeKm} (janela de latitude em cima
 *     de uma lista ordenada + haversine);
 *  2. descarta de cara quem já não fecha nem em espaço livre (a difração só
 *     piora o enlace);
 *  3. só então calcula o enlace com relevo. Candidatos rodam em paralelo.
 */
public final class CoverageCalculator {

    private static final double KM_PER_DEGREE = 111.195;

    private CoverageCalculator() {
    }

    public static CoverageMatrix compute(List<GeoSite> candidates, List<GeoSite> assets,
                                         RadioParams p, PropagationModel model) {
        p.validate();
        final double budget = p.linkBudgetDb();
        final int nC = candidates.size(), nA = assets.size();

        // ativos ordenados por latitude, para a janela de busca
        Integer[] order = new Integer[nA];
        for (int i = 0; i < nA; i++) order[i] = i;
        Arrays.sort(order, (a, b) -> Double.compare(assets.get(a).lat(), assets.get(b).lat()));
        final double[] sortedLat = new double[nA];
        final int[] sortedIdx = new int[nA];
        for (int i = 0; i < nA; i++) {
            sortedIdx[i] = order[i];
            sortedLat[i] = assets.get(order[i]).lat();
        }

        final double dLat = p.maxRangeKm / KM_PER_DEGREE;
        final int[][] idx = new int[nC][];
        final float[][] loss = new float[nC][];
        final LongAdder evaluated = new LongAdder(), missing = new LongAdder();

        IntStream.range(0, nC).parallel().forEach(c -> {
            GeoSite g = candidates.get(c);
            int start = lowerBound(sortedLat, g.lat() - dLat);
            long[] packed = new long[16];
            int count = 0;
            for (int j = start; j < nA && sortedLat[j] <= g.lat() + dLat; j++) {
                int ai = sortedIdx[j];
                GeoSite a = assets.get(ai);
                double d = Geo.distanceKm(g.lat(), g.lon(), a.lat(), a.lon());
                if (d > p.maxRangeKm) continue;
                if (FreeSpaceModel.fsplDb(p.frequencyMhz, d) > budget) continue;
                LinkResult r = model.evaluate(g.lat(), g.lon(), a.lat(), a.lon(), p);
                evaluated.increment();
                if (r.terrainMissing()) missing.increment();
                if (r.pathLossDb() <= budget) {
                    if (count == packed.length) packed = Arrays.copyOf(packed, count * 2);
                    packed[count++] = ((long) ai << 32) | (Float.floatToIntBits((float) r.pathLossDb()) & 0xFFFFFFFFL);
                }
            }
            Arrays.sort(packed, 0, count); // ordena por índice do ativo
            idx[c] = new int[count];
            loss[c] = new float[count];
            for (int k = 0; k < count; k++) {
                idx[c][k] = (int) (packed[k] >>> 32);
                loss[c][k] = Float.intBitsToFloat((int) packed[k]);
            }
        });

        return new CoverageMatrix(candidates, assets, p.copy(), idx, loss, evaluated.sum(), missing.sum());
    }

    private static int lowerBound(double[] sorted, double value) {
        int lo = 0, hi = sorted.length;
        while (lo < hi) {
            int mid = (lo + hi) >>> 1;
            if (sorted[mid] < value) lo = mid + 1;
            else hi = mid;
        }
        return lo;
    }
}
