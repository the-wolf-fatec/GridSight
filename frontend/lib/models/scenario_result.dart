import 'candidate_site.dart';
import 'coverage_params.dart';
import 'terrain_analysis.dart';

/// Resultado de uma execução do algoritmo de otimização (um "cenário"),
/// usado tanto na tela de resultado quanto na comparação de cenários (US8).
class ScenarioResult {
  final String id;
  final String label;
  final DateTime executedAt;
  final CoverageParams params;
  final List<CandidateSite> chosenGateways;
  final int totalAssets;
  final int coveredAssets;
  final Duration processingTime;

  /// Detalhes do cálculo com relevo (quem atende quem, ativos perdidos por
  /// morros, áreas de cobertura). Null em cenários só por distância ou
  /// carregados do histórico do banco.
  final TerrainAnalysis? terrain;

  const ScenarioResult({
    required this.id,
    required this.label,
    required this.executedAt,
    required this.params,
    required this.chosenGateways,
    required this.totalAssets,
    required this.coveredAssets,
    required this.processingTime,
    this.terrain,
  });

  ScenarioResult withTerrain(TerrainAnalysis? t) => ScenarioResult(
        id: id,
        label: label,
        executedAt: executedAt,
        params: params,
        chosenGateways: chosenGateways,
        totalAssets: totalAssets,
        coveredAssets: coveredAssets,
        processingTime: processingTime,
        terrain: t,
      );

  double get coveragePercent => totalAssets == 0 ? 0 : coveredAssets / totalAssets;
  int get gatewaysUsed => chosenGateways.length;
}
