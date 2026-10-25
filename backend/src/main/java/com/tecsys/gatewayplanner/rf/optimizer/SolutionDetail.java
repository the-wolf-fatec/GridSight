package com.tecsys.gatewayplanner.rf.optimizer;

import com.tecsys.gatewayplanner.rf.CoverageMatrix;

import java.util.ArrayList;
import java.util.BitSet;
import java.util.List;

/**
 * Uma configuração de gateways e o que ela atende. Cada ativo coberto é
 * atribuído ao gateway com MENOR perda de propagação (melhor sinal).
 */
public final class SolutionDetail {
    public final String note;
    public final List<Integer> gateways;       // índices de candidato, na ordem de escolha
    public final int totalAssets;
    public final int covered;
    public final int[] servingGateway;         // por ativo: índice de candidato, ou -1
    public final float[] servingPathLossDb;    // por ativo: NaN se descoberto
    public final int[] individualCovered;      // por gateway: quantos ativos alcançaria SOZINHO
    public final int[] assignedCount;          // por gateway: quantos ativos atende de fato
    public final int[] exclusiveCount;         // por gateway: ativos que só ele alcança

    private SolutionDetail(String note, List<Integer> gateways, int totalAssets, int covered,
                           int[] serving, float[] servingLoss, int[] individual, int[] assigned, int[] exclusive) {
        this.note = note;
        this.gateways = gateways;
        this.totalAssets = totalAssets;
        this.covered = covered;
        this.servingGateway = serving;
        this.servingPathLossDb = servingLoss;
        this.individualCovered = individual;
        this.assignedCount = assigned;
        this.exclusiveCount = exclusive;
    }

    public double coverageFraction() {
        return totalAssets == 0 ? 0 : (double) covered / totalAssets;
    }

    public static SolutionDetail of(CoverageMatrix m, List<Integer> gateways, String note) {
        int nA = m.assetCount(), g = gateways.size();
        int[] serving = new int[nA];
        float[] servingLoss = new float[nA];
        java.util.Arrays.fill(serving, -1);
        java.util.Arrays.fill(servingLoss, Float.NaN);
        int[] reach = new int[nA]; // quantos gateways escolhidos alcançam cada ativo
        int[] individual = new int[g];

        for (int gi = 0; gi < g; gi++) {
            int c = gateways.get(gi);
            int[] ids = m.coveredAssets(c);
            individual[gi] = ids.length;
            for (int a : ids) {
                reach[a]++;
                float pl = m.pathLoss(c, a);
                if (serving[a] < 0 || pl < servingLoss[a]) {
                    serving[a] = c;
                    servingLoss[a] = pl;
                }
            }
        }

        int[] assigned = new int[g], exclusive = new int[g];
        int covered = 0;
        for (int a = 0; a < nA; a++) {
            if (serving[a] < 0) continue;
            covered++;
            int gi = gateways.indexOf(serving[a]);
            assigned[gi]++;
        }
        for (int gi = 0; gi < g; gi++) {
            for (int a : m.coveredAssets(gateways.get(gi))) if (reach[a] == 1) exclusive[gi]++;
        }
        return new SolutionDetail(note, new ArrayList<>(gateways), nA, covered, serving, servingLoss, individual, assigned, exclusive);
    }

    public BitSet coveredSet() {
        BitSet bs = new BitSet(totalAssets);
        for (int a = 0; a < totalAssets; a++) if (servingGateway[a] >= 0) bs.set(a);
        return bs;
    }
}
