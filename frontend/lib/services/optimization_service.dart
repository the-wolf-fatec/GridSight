import '../models/asset.dart';
import '../models/candidate_site.dart';
import '../models/coverage_params.dart';
import '../models/scenario_result.dart';
import 'geo_utils.dart';

/// Serviço responsável por resolver o problema de posicionamento de gateways
/// (US5): dado um conjunto de ativos a cobrir e um conjunto de locais
/// candidatos, escolher um subconjunto eficiente de candidatos que maximize
/// a cobertura, evitando testar todas as combinações possíveis (força bruta).
///
/// Estratégia: heurística gulosa de cobertura máxima (maximum coverage
/// greedy), amplamente usada para o "Maximum Coverage Problem" (NP-difícil).
/// A cada passo escolhe o candidato que cobre o maior número de ativos ainda
/// não cobertos, dentro do alcance de rádio configurado, até atingir a meta
/// de cobertura ou o limite máximo de gateways.
class OptimizationService {
  ScenarioResult run({
    required String label,
    required List<Asset> assets,
    required List<CandidateSite> candidates,
    required CoverageParams params,
  }) {
    final stopwatch = Stopwatch()..start();
    final effectiveRange = params.effectiveRangeKm;

    // Pré-calcula, para cada candidato, quais ativos ele cobre dentro do alcance efetivo.
    final Map<String, Set<int>> coverageMap = {
      for (final c in candidates)
        c.id: {
          for (var i = 0; i < assets.length; i++)
            if (GeoUtils.distanceKm(c.latitude, c.longitude, assets[i].latitude, assets[i].longitude) <=
                effectiveRange)
              i,
        },
    };

    final Set<int> uncovered = {for (var i = 0; i < assets.length; i++) i};
    final List<CandidateSite> chosen = [];
    final targetCovered = (assets.length * params.minCoverageTarget).ceil();

    final remainingCandidates = List<CandidateSite>.from(candidates);

    while (chosen.length < params.maxGateways &&
        uncovered.isNotEmpty &&
        (assets.length - uncovered.length) < targetCovered &&
        remainingCandidates.isNotEmpty) {
      CandidateSite? best;
      int bestGain = 0;

      for (final c in remainingCandidates) {
        final gain = coverageMap[c.id]!.intersection(uncovered).length;
        if (gain > bestGain) {
          bestGain = gain;
          best = c;
        }
      }

      if (best == null || bestGain == 0) break;

      chosen.add(best);
      uncovered.removeAll(coverageMap[best.id]!);
      remainingCandidates.remove(best);
    }

    stopwatch.stop();

    return ScenarioResult(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      executedAt: DateTime.now(),
      params: params,
      chosenGateways: chosen,
      totalAssets: assets.length,
      coveredAssets: assets.length - uncovered.length,
      processingTime: stopwatch.elapsed,
    );
  }

  /// Retorna o conjunto de ativos cobertos por uma lista de gateways escolhidos,
  /// útil para desenhar a área de cobertura no mapa.
  Set<int> coveredAssetIndexes({
    required List<Asset> assets,
    required List<CandidateSite> gateways,
    required double rangeKm,
  }) {
    final covered = <int>{};
    for (final g in gateways) {
      for (var i = 0; i < assets.length; i++) {
        if (GeoUtils.distanceKm(g.latitude, g.longitude, assets[i].latitude, assets[i].longitude) <= rangeKm) {
          covered.add(i);
        }
      }
    }
    return covered;
  }
}
