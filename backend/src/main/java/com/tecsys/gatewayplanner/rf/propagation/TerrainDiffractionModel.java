package com.tecsys.gatewayplanner.rf.propagation;

import com.tecsys.gatewayplanner.rf.Geo;
import com.tecsys.gatewayplanner.rf.RadioParams;
import com.tecsys.gatewayplanner.rf.terrain.TerrainProvider;

/**
 * Perda de propagação considerando o relevo entre gateway e dispositivo:
 *
 *   perda = espaço livre + perda por difração nos obstáculos do perfil
 *
 * - O perfil do terreno é amostrado ao longo do enlace (a cada ~30 m ou
 *   distância/200, o que for maior) usando o {@link TerrainProvider}.
 * - Soma-se o abaulamento da Terra (raio efetivo k = 4/3).
 * - Os obstáculos são tratados como "gumes de faca" pelo método de Deygout
 *   (ITU-R P.526): o obstáculo principal e, recursivamente, até um em cada
 *   lado dele (no máximo 3 gumes), com a zona de Fresnel considerada via o
 *   parâmetro v. Se a primeira zona de Fresnel está livre, a difração é ~0 dB.
 *
 * Limitações (por isso é o "nível 1" e não o Longley-Rice do Radio Mobile):
 * não modela vegetação, prédios nem reflexão no solo; o DEM mostra o terreno,
 * não as construções. Use {@link RadioParams#fadeMarginDb} para reservar uma
 * margem para isso, e calibre comparando alguns enlaces com o Radio Mobile.
 */
public final class TerrainDiffractionModel implements PropagationModel {

    /** Fator k do raio efetivo da Terra (4/3 = atmosfera padrão). */
    private static final double K_FACTOR = 4.0 / 3.0;
    private static final double EARTH_RADIUS_M = Geo.EARTH_RADIUS_KM * 1000;
    private static final double MIN_STEP_M = 60;
    private static final int TARGET_SAMPLES = 120;
    /** Abaixo disso não vale a pena amostrar relevo. */
    private static final double MIN_TERRAIN_DISTANCE_KM = 0.05;
    /** Limiar de v abaixo do qual a difração é desprezível (ITU-R P.526). */
    private static final double V_MIN = -0.78;
    /**
     * Distância mínima (m) entre o obstáculo principal e um secundário. Sem isso,
     * duas amostras vizinhas do MESMO pico (a ~30 m uma da outra) seriam contadas
     * como dois gumes de faca e a perda sairia ~10 dB maior do que a real.
     */
    private static final double MIN_EDGE_SEPARATION_M = 100;

    private final TerrainProvider terrain;

    public TerrainDiffractionModel(TerrainProvider terrain) {
        this.terrain = terrain;
    }

    @Override
    public LinkResult evaluate(double txLat, double txLon, double rxLat, double rxLon, RadioParams p) {
        double dKm = Geo.distanceKm(txLat, txLon, rxLat, rxLon);
        double fspl = FreeSpaceModel.fsplDb(p.frequencyMhz, dKm);
        if (!p.useTerrain || dKm < MIN_TERRAIN_DISTANCE_KM) {
            return new LinkResult(fspl, dKm, false, 0);
        }

        double dM = dKm * 1000;
        double step = Math.max(MIN_STEP_M, dM / TARGET_SAMPLES);
        int n = Math.max(2, (int) Math.ceil(dM / step));
        double[] x = new double[n + 1];
        double[] y = new double[n + 1];

        double e0 = terrain.elevationM(txLat, txLon);
        double en = terrain.elevationM(rxLat, rxLon);
        if (Double.isNaN(e0) || Double.isNaN(en)) {
            return new LinkResult(fspl, dKm, true, 0);
        }

        // Rejeição rápida: com 1/3 das amostras já dá para descartar a maioria dos enlaces
        // bloqueados. Menos amostras só podem perder obstáculos (a perda real é igual ou maior),
        // então um enlace que já estoura o orçamento assim não fecharia de qualquer jeito.
        double budget = p.linkBudgetDb();
        if (n >= 40 && fspl < budget) {
            int nc = n / 3;
            double[] xc = new double[nc + 1], yc = new double[nc + 1];
            double last = e0;
            for (int i = 1; i < nc; i++) {
                double f = (double) i / nc;
                double e = terrain.elevationFastM(txLat + (rxLat - txLat) * f, txLon + (rxLon - txLon) * f);
                if (Double.isNaN(e)) e = last;
                else last = e;
                xc[i] = dM * f;
                yc[i] = e + xc[i] * (dM - xc[i]) / (2 * K_FACTOR * EARTH_RADIUS_M);
            }
            xc[0] = 0;
            yc[0] = e0 + p.gatewayHeightM;
            xc[nc] = dM;
            yc[nc] = en + p.deviceHeightM;
            double lam = 299.792458 / p.frequencyMhz;
            int sepC = Math.max(2, (int) Math.ceil(MIN_EDGE_SEPARATION_M / (dM / nc)));
            double dc = deygout(xc, yc, 0, nc, 1, nc - 1, sepC, lam, 2);
            if (fspl + dc > budget) return new LinkResult(fspl + dc, dKm, false, dc);
        }

        int missing = 0;
        double lastValid = e0;
        for (int i = 1; i < n; i++) {
            double f = (double) i / n;
            double e = terrain.elevationFastM(txLat + (rxLat - txLat) * f, txLon + (rxLon - txLon) * f);
            if (Double.isNaN(e)) {
                missing++;
                e = lastValid;
            } else {
                lastValid = e;
            }
            x[i] = dM * f;
            y[i] = e + x[i] * (dM - x[i]) / (2 * K_FACTOR * EARTH_RADIUS_M);
        }
        if (missing > (n - 1) / 2) {
            return new LinkResult(fspl, dKm, true, 0);
        }
        x[0] = 0;
        y[0] = e0 + p.gatewayHeightM;
        x[n] = dM;
        y[n] = en + p.deviceHeightM;

        double lambda = 299.792458 / p.frequencyMhz;
        int sep = Math.max(2, (int) Math.ceil(MIN_EDGE_SEPARATION_M / (dM / n)));
        double diffraction = deygout(x, y, 0, n, 1, n - 1, sep, lambda, 2);
        return new LinkResult(fspl + diffraction, dKm, false, diffraction);
    }

    /**
     * Perda por difração no trecho entre os índices a e b (pontas da linha de visada),
     * procurando obstáculos só nos índices [lo, hi], com até {@code depth} níveis.
     */
    static double deygout(double[] x, double[] y, int a, int b, int lo, int hi, int sep, double lambda, int depth) {
        if (hi < lo) return 0;
        double xa = x[a], ya = y[a], span = x[b] - xa;
        double slope = (y[b] - ya) / span;

        int best = -1;
        double bestV = Double.NEGATIVE_INFINITY;
        for (int k = lo; k <= hi; k++) {
            double d1 = x[k] - xa, d2 = x[b] - x[k];
            double h = y[k] - (ya + slope * d1); // altura do obstáculo acima da linha de visada
            double v = h * Math.sqrt(2 * (d1 + d2) / (lambda * d1 * d2));
            if (v > bestV) {
                bestV = v;
                best = k;
            }
        }
        if (best < 0 || bestV <= V_MIN) return 0;

        double loss = knifeEdgeLossDb(bestV);
        if (depth > 1) {
            loss += deygout(x, y, a, best, a + 1, best - sep, sep, lambda, depth - 1);
            loss += deygout(x, y, best, b, best + sep, b - 1, sep, lambda, depth - 1);
        }
        return loss;
    }

    /** J(v) do ITU-R P.526 (válida para v > -0.78). */
    public static double knifeEdgeLossDb(double v) {
        if (v <= V_MIN) return 0;
        double t = v - 0.1;
        return 6.9 + 20 * Math.log10(Math.sqrt(t * t + 1) + t);
    }
}
