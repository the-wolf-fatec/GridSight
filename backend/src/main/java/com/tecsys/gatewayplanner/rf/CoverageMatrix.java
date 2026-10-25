package com.tecsys.gatewayplanner.rf;

import java.util.BitSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Para cada local candidato, quais ativos ele cobre e com que perda de
 * propagação. É calculada UMA vez por cenário; a otimização e os resultados
 * só consultam esta matriz (sem recalcular RF).
 */
public final class CoverageMatrix {

    private final List<GeoSite> candidates;
    private final List<GeoSite> assets;
    private final RadioParams params;
    private final int[][] assetIdx;      // por candidato: índices dos ativos cobertos (crescente)
    private final float[][] pathLossDb;  // alinhado com assetIdx
    private final BitSet[] coverage;     // por candidato
    private final long linksEvaluated;
    private final long linksMissingTerrain;
    private final Map<String, Integer> candidateIndexById = new HashMap<>();

    CoverageMatrix(List<GeoSite> candidates, List<GeoSite> assets, RadioParams params,
                   int[][] assetIdx, float[][] pathLossDb, long linksEvaluated, long linksMissingTerrain) {
        this.candidates = candidates;
        this.assets = assets;
        this.params = params;
        this.assetIdx = assetIdx;
        this.pathLossDb = pathLossDb;
        this.linksEvaluated = linksEvaluated;
        this.linksMissingTerrain = linksMissingTerrain;
        this.coverage = new BitSet[candidates.size()];
        for (int c = 0; c < coverage.length; c++) {
            BitSet bs = new BitSet(assets.size());
            for (int a : assetIdx[c]) bs.set(a);
            coverage[c] = bs;
            candidateIndexById.put(candidates.get(c).id(), c);
        }
    }

    public List<GeoSite> candidates() { return candidates; }
    public List<GeoSite> assets() { return assets; }
    public RadioParams params() { return params; }
    public int candidateCount() { return candidates.size(); }
    public int assetCount() { return assets.size(); }
    public BitSet coverageOf(int candidate) { return coverage[candidate]; }
    public int[] coveredAssets(int candidate) { return assetIdx[candidate]; }
    public long linksEvaluated() { return linksEvaluated; }
    public long linksMissingTerrain() { return linksMissingTerrain; }

    /** Índice do candidato pelo id, ou -1. */
    public int indexOfCandidate(String id) {
        return candidateIndexById.getOrDefault(id, -1);
    }

    /** Perda de propagação (dB) candidato -> ativo, ou NaN se o ativo não é coberto por ele. */
    public float pathLoss(int candidate, int asset) {
        int[] idx = assetIdx[candidate];
        int pos = java.util.Arrays.binarySearch(idx, asset);
        return pos < 0 ? Float.NaN : pathLossDb[candidate][pos];
    }
}
