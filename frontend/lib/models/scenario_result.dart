import 'candidate_site.dart';
import 'coverage_params.dart';

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

  const ScenarioResult({
    required this.id,
    required this.label,
    required this.executedAt,
    required this.params,
    required this.chosenGateways,
    required this.totalAssets,
    required this.coveredAssets,
    required this.processingTime,
  });

  double get coveragePercent => totalAssets == 0 ? 0 : coveredAssets / totalAssets;
  int get gatewaysUsed => chosenGateways.length;
}
