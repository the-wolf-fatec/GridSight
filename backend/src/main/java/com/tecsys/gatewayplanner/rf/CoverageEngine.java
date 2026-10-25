package com.tecsys.gatewayplanner.rf;

import com.tecsys.gatewayplanner.rf.optimizer.OptimizerConstraints;
import com.tecsys.gatewayplanner.rf.optimizer.PlacementOptimizer;
import com.tecsys.gatewayplanner.rf.optimizer.SolutionDetail;
import com.tecsys.gatewayplanner.rf.propagation.FreeSpaceModel;
import com.tecsys.gatewayplanner.rf.propagation.PropagationModel;
import com.tecsys.gatewayplanner.rf.propagation.TerrainDiffractionModel;
import com.tecsys.gatewayplanner.rf.terrain.TerrainProvider;

import java.util.ArrayList;
import java.util.List;

/**
 * Fachada do motor de RF: calcula a matriz de cobertura e otimiza.
 * Não depende do Spring — o {@code CoverageService} só carrega os dados do
 * banco e chama aqui.
 */
public final class CoverageEngine {

    /** [0] = configuração principal; demais = alternativas. */
    public record Result(CoverageMatrix matrix, List<SolutionDetail> solutions, long elapsedMs) {
        public SolutionDetail main() {
            return solutions.get(0);
        }
    }

    private CoverageEngine() {
    }

    public static PropagationModel modelFor(RadioParams p, TerrainProvider terrain) {
        return p.useTerrain ? new TerrainDiffractionModel(terrain) : new FreeSpaceModel();
    }

    public static Result optimize(List<GeoSite> candidates, List<GeoSite> assets, RadioParams p,
                                  OptimizerConstraints oc, int alternatives, TerrainProvider terrain) {
        long t0 = System.nanoTime();
        CoverageMatrix m = CoverageCalculator.compute(candidates, assets, p, modelFor(p, terrain));
        List<SolutionDetail> solutions = PlacementOptimizer.optimize(m, oc, alternatives);
        return new Result(m, solutions, (System.nanoTime() - t0) / 1_000_000);
    }

    /** Avalia uma escolha manual de gateways (ids de candidato), sem otimizar. */
    public static Result evaluate(List<GeoSite> candidates, List<GeoSite> assets, RadioParams p,
                                  List<String> gatewayIds, TerrainProvider terrain) {
        long t0 = System.nanoTime();
        CoverageMatrix m = CoverageCalculator.compute(candidates, assets, p, modelFor(p, terrain));
        List<Integer> chosen = new ArrayList<>();
        for (String id : gatewayIds) {
            int i = m.indexOfCandidate(id);
            if (i >= 0 && !chosen.contains(i)) chosen.add(i);
        }
        List<SolutionDetail> one = List.of(SolutionDetail.of(m, chosen, "Seleção manual"));
        return new Result(m, one, (System.nanoTime() - t0) / 1_000_000);
    }
}
