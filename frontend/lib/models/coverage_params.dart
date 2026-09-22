import 'dart:math' as math;

/// Parâmetros técnicos de cobertura de radiofrequência,
/// parametrizáveis pelo usuário (US4).
class CoverageParams {
  final double rangeKm; // alcance de referência do gateway (calibrado a referencePowerDbm), em km
  final double transmissionPowerDbm; // potência de transmissão
  final double minCoverageTarget; // meta de % de cobertura desejada (0-1)
  final int maxGateways; // limite máximo de gateways a instalar

  /// Potência de referência na qual [rangeKm] foi calibrado.
  static const double referencePowerDbm = 20;

  const CoverageParams({
    this.rangeKm = 2.5,
    this.transmissionPowerDbm = 20,
    this.minCoverageTarget = 1.0,
    this.maxGateways = 12,
  });

  /// Alcance efetivo de cobertura, considerando a potência de transmissão
  /// configurada. Usa o modelo de perda de espaço livre (free-space path
  /// loss): a cada 6 dB adicionais de potência, o alcance máximo dobra.
  /// É este valor — e não [rangeKm] diretamente — que o algoritmo de
  /// otimização e o mapa usam para calcular a cobertura.
  double get effectiveRangeKm {
    final deltaDb = transmissionPowerDbm - referencePowerDbm;
    final factor = math.pow(10, deltaDb / 20).toDouble();
    return rangeKm * factor;
  }

  CoverageParams copyWith({
    double? rangeKm,
    double? transmissionPowerDbm,
    double? minCoverageTarget,
    int? maxGateways,
  }) {
    return CoverageParams(
      rangeKm: rangeKm ?? this.rangeKm,
      transmissionPowerDbm: transmissionPowerDbm ?? this.transmissionPowerDbm,
      minCoverageTarget: minCoverageTarget ?? this.minCoverageTarget,
      maxGateways: maxGateways ?? this.maxGateways,
    );
  }
}
