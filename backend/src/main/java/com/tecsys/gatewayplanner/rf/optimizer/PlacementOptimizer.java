package com.tecsys.gatewayplanner.rf.optimizer;

import com.tecsys.gatewayplanner.rf.CoverageMatrix;

import java.util.ArrayList;
import java.util.BitSet;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.PriorityQueue;
import java.util.Set;

/**
 * Escolhe onde instalar os gateways olhando a contribuição CONJUNTA deles
 * (não cada um isolado):
 *
 *  1. Guloso por ganho marginal: a cada passo entra o candidato que cobre mais
 *     ativos AINDA descobertos (avaliação preguiçosa/CELF, pois o ganho só
 *     diminui). Respeita limite de gateways, meta de cobertura, locais
 *     proibidos e obrigatórios.
 *  2. Poda: remove gateway que ficou redundante (tudo que ele cobre outros já cobrem).
 *  3. Troca local: tenta trocar cada gateway por outro candidato que aumente a
 *     cobertura total; repete até não melhorar (poucas passadas).
 *
 * Alternativas: reroda a busca proibindo, um de cada vez, os gateways da
 * solução principal; se ainda faltar alternativa, proíbe grupos inteiros.
 */
public final class PlacementOptimizer {

    private PlacementOptimizer() {
    }

    /** Retorna [principal, alternativa1, ...]; a lista tem no máximo 1 + {@code alternatives} itens. */
    public static List<SolutionDetail> optimize(CoverageMatrix m, OptimizerConstraints oc, int alternatives) {
        int nC = m.candidateCount();
        boolean[] banned = new boolean[nC];
        for (String id : oc.forbiddenCandidateIds) {
            int i = m.indexOfCandidate(id);
            if (i >= 0) banned[i] = true;
        }
        List<Integer> required = new ArrayList<>();
        for (String id : oc.requiredCandidateIds) {
            int i = m.indexOfCandidate(id);
            if (i >= 0 && !banned[i]) required.add(i);
        }
        Set<Integer> requiredSet = new HashSet<>(required);

        List<Integer> mainChosen = solve(m, oc, banned, required);
        List<SolutionDetail> out = new ArrayList<>();
        out.add(SolutionDetail.of(m, mainChosen, "Configuração principal"));

        int want = Math.max(0, Math.min(alternatives, 5));
        if (want == 0 || mainChosen.isEmpty()) return out;

        List<SolutionDetail> alts = new ArrayList<>();
        Set<Set<Integer>> seen = new HashSet<>();
        seen.add(new HashSet<>(mainChosen));

        List<Integer> removable = new ArrayList<>();
        for (int g : mainChosen) if (!requiredSet.contains(g)) removable.add(g);

        // 1) alternativas "sem o gateway X"
        for (int g : removable) {
            if (alts.size() >= want) break;
            tryAlternative(m, oc, banned, required, Set.of(g), "Sem " + m.candidates().get(g).name(), seen, alts);
        }
        // 2) se faltar, bloqueia grupos cada vez maiores (configurações mais diferentes)
        Set<Integer> cumulative = new LinkedHashSet<>(removable);
        for (int round = 0; alts.size() < want && round < want + 2 && !cumulative.isEmpty(); round++) {
            int before = alts.size();
            tryAlternative(m, oc, banned, required, cumulative, "Sem nenhum dos gateways anteriores (" + (round + 1) + ")", seen, alts);
            if (alts.size() > before) cumulative.addAll(alts.get(alts.size() - 1).gateways);
            else break;
            cumulative.removeAll(requiredSet);
        }

        alts.sort(Comparator.comparingInt((SolutionDetail s) -> -s.covered).thenComparingInt(s -> s.gateways.size()));
        out.addAll(alts);
        return out;
    }

    private static void tryAlternative(CoverageMatrix m, OptimizerConstraints oc, boolean[] baseBanned, List<Integer> required,
                                       Set<Integer> extraBans, String note, Set<Set<Integer>> seen, List<SolutionDetail> alts) {
        boolean[] banned = baseBanned.clone();
        for (int g : extraBans) banned[g] = true;
        List<Integer> chosen = solve(m, oc, banned, required);
        if (chosen.isEmpty() || !seen.add(new HashSet<>(chosen))) return;
        SolutionDetail s = SolutionDetail.of(m, chosen, note);
        if (s.covered > 0) alts.add(s);
    }

    /** Uma execução completa: guloso + poda + troca local. */
    static List<Integer> solve(CoverageMatrix m, OptimizerConstraints oc, boolean[] banned, List<Integer> required) {
        int total = m.assetCount();
        int target = (int) Math.ceil(total * Math.min(1.0, Math.max(0.0, oc.minCoverageTarget)) - 1e-9);
        int maxG = Math.max(1, oc.maxGateways);

        BitSet covered = new BitSet(total);
        List<Integer> chosen = new ArrayList<>();
        boolean[] isChosen = new boolean[m.candidateCount()];
        for (int r : required) {
            if (!isChosen[r]) {
                chosen.add(r);
                isChosen[r] = true;
                covered.or(m.coverageOf(r));
            }
        }

        // guloso preguiçoso
        record Entry(int c, int gain, int stamp) {
        }
        Comparator<Entry> cmp = Comparator.comparingInt((Entry e) -> -e.gain())
                .thenComparingInt(e -> -m.coverageOf(e.c()).cardinality())
                .thenComparingInt(Entry::c);
        PriorityQueue<Entry> pq = new PriorityQueue<>(cmp);
        for (int c = 0; c < m.candidateCount(); c++) {
            if (banned[c] || isChosen[c]) continue;
            int gain = gain(m.coverageOf(c), covered);
            if (gain > 0) pq.add(new Entry(c, gain, 0));
        }
        int round = 0;
        while (chosen.size() < maxG && covered.cardinality() < Math.max(target, 1) && covered.cardinality() < total && !pq.isEmpty()) {
            Entry top = pq.poll();
            if (top.stamp() != round) {
                int g = gain(m.coverageOf(top.c()), covered);
                if (g > 0) pq.add(new Entry(top.c(), g, round));
                continue;
            }
            chosen.add(top.c());
            isChosen[top.c()] = true;
            covered.or(m.coverageOf(top.c()));
            round++;
        }

        prune(m, chosen, required);
        localSwap(m, chosen, required, banned, isChosen);
        prune(m, chosen, required);
        return chosen;
    }

    private static int gain(BitSet cov, BitSet covered) {
        BitSet t = (BitSet) cov.clone();
        t.andNot(covered);
        return t.cardinality();
    }

    /** Remove gateways redundantes (nenhum ativo depende só deles). */
    private static void prune(CoverageMatrix m, List<Integer> chosen, List<Integer> required) {
        int[] cnt = new int[m.assetCount()];
        for (int c : chosen) for (int a : m.coveredAssets(c)) cnt[a]++;
        for (int i = chosen.size() - 1; i >= 0; i--) {
            int c = chosen.get(i);
            if (required.contains(c)) continue;
            boolean redundant = true;
            for (int a : m.coveredAssets(c)) {
                if (cnt[a] < 2) {
                    redundant = false;
                    break;
                }
            }
            if (redundant) {
                for (int a : m.coveredAssets(c)) cnt[a]--;
                chosen.remove(i);
            }
        }
    }

    /** Troca cada gateway por outro candidato quando isso aumenta a cobertura total. */
    private static void localSwap(CoverageMatrix m, List<Integer> chosen, List<Integer> required, boolean[] banned, boolean[] isChosen) {
        for (int pass = 0; pass < 3; pass++) {
            boolean improved = false;
            for (int p = 0; p < chosen.size(); p++) {
                int current = chosen.get(p);
                if (required.contains(current)) continue;
                BitSet others = new BitSet(m.assetCount());
                for (int i = 0; i < chosen.size(); i++) if (i != p) others.or(m.coverageOf(chosen.get(i)));

                int best = current;
                int bestGain = gain(m.coverageOf(current), others);
                for (int c = 0; c < m.candidateCount(); c++) {
                    if (banned[c] || isChosen[c]) continue;
                    int g = gain(m.coverageOf(c), others);
                    if (g > bestGain) {
                        bestGain = g;
                        best = c;
                    }
                }
                if (best != current) {
                    isChosen[current] = false;
                    isChosen[best] = true;
                    chosen.set(p, best);
                    improved = true;
                }
            }
            if (!improved) break;
        }
    }
}
