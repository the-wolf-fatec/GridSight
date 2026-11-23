import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/elevation_profile.dart';
import '../services/planning_api_service.dart';
import '../theme/app_theme.dart';

/// Abre o perfil de elevação do enlace entre dois pontos (gateway e ativo):
/// mostra o terreno, a linha de visada e a folga, para ver ONDE o morro bloqueia o sinal.
Future<void> showElevationProfile(
  BuildContext context, {
  required PlanningApiService api,
  required String fromName,
  required double fromLat,
  required double fromLon,
  required String toName,
  required double toLat,
  required double toLon,
  double gatewayHeightM = 6,
  double? rxDbm, // sinal que o cálculo estimou para este enlace (null = ativo sem sinal)
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child: _ProfileBody(
          future: api.elevationProfile(lat1: fromLat, lon1: fromLon, lat2: toLat, lon2: toLon, gatewayHeightM: gatewayHeightM),
          fromName: fromName,
          toName: toName,
          rxDbm: rxDbm,
        ),
      ),
    ),
  );
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.future, required this.fromName, required this.toName, this.rxDbm});
  final double? rxDbm;
  final Future<ElevationProfile> future;
  final String fromName;
  final String toName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.terrain, color: AppColors.coverage),
          const SizedBox(width: 8),
          const Expanded(child: Text('Perfil de elevação do enlace', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close), tooltip: 'Fechar'),
        ]),
        Text('$fromName  ->  $toName', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 12),
        Flexible(
          child: FutureBuilder<ElevationProfile>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return SizedBox(height: 160, child: Center(child: Text('Não consegui obter o perfil: ${snap.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.alert, fontSize: 13))));
              }
              final p = snap.data!;
              if (!p.hasData || p.samples.length < 2) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: Text('Sem dados de relevo (.hgt) nesta região. Baixe o relevo com o script de dados e reinicie o backend.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                );
              }
              return SingleChildScrollView(child: _ProfileChart(profile: p, rxDbm: rxDbm));
            },
          ),
        ),
      ]),
    );
  }
}

class _ProfileChart extends StatelessWidget {
  const _ProfileChart({required this.profile, this.rxDbm});
  final ElevationProfile profile;
  final double? rxDbm;

  @override
  Widget build(BuildContext context) {
    final s = profile.samples;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in s) {
      for (final v in [p.groundM, p.lineOfSightM, p.fresnelLowerM]) {
        if (v < minY) minY = v;
        if (v > maxY) maxY = v;
      }
    }
    final pad = ((maxY - minY) * 0.08).clamp(2.0, 1000.0);
    minY = (minY - pad).floorToDouble();
    maxY = (maxY + pad).ceilToDouble();

    final (statusText, statusColor, statusIcon) = (profile.blocked && rxDbm != null)
        ? ('Morro no caminho (${profile.minClearanceM.abs().toStringAsFixed(0)} m acima da linha de visada, a ${profile.worstDistanceKm.toStringAsFixed(2)} km do gateway), mas o ativo É atendido: o sinal passa por difração e chega com ${rxDbm!.toStringAsFixed(0)} dBm (mínimo -120 dBm, folga de ${(rxDbm! + 120).toStringAsFixed(0)} dB). Enlace longo e obstruído: fica no limite.', AppColors.energy, Icons.warning_amber_rounded)
        : profile.blocked
        ? ('Bloqueado: o terreno passa ${profile.minClearanceM.abs().toStringAsFixed(0)} m acima da linha de visada, a ${profile.worstDistanceKm.toStringAsFixed(2)} km do gateway.', AppColors.alert, Icons.block)
        : profile.fresnelObstructed
            ? ('Visada livre (folga mínima de ${profile.minClearanceM.toStringAsFixed(0)} m), mas o terreno invade a zona de Fresnel: o sinal pode ficar degradado.', AppColors.energy, Icons.warning_amber_rounded)
            : ('Linha de visada livre, com folga mínima de ${profile.minClearanceM.toStringAsFixed(0)} m.', AppColors.coverage, Icons.check_circle_outline);

    LineChartBarData line(List<FlSpot> spots, Color color, {double width = 2, List<int>? dash, bool fill = false}) => LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: width,
          dotData: const FlDotData(show: false),
          dashArray: dash,
          belowBarData: BarAreaData(show: fill, color: color.withOpacity(0.35)),
        );

    final ground = [for (final p in s) FlSpot(p.distanceKm, p.groundM)];
    final los = [for (final p in s) FlSpot(p.distanceKm, p.lineOfSightM)];
    final fres = [for (final p in s) FlSpot(p.distanceKm, p.fresnelLowerM)];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: statusColor.withOpacity(0.5))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(statusIcon, size: 18, color: statusColor),
          const SizedBox(width: 8),
          Expanded(child: Text(statusText, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary))),
        ]),
      ),
      const SizedBox(height: 14),
      SizedBox(
        height: 260,
        child: LineChart(LineChartData(
          minX: 0,
          maxX: profile.distanceKm,
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => const FlLine(color: AppColors.divider, strokeWidth: 0.6)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              axisNameWidget: const Text('metros', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, meta) => Text('${v.round()}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: const Text('distância do gateway (km)', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: true),
          lineBarsData: [
            line(ground, const Color(0xFFB08968), width: 2.2, fill: true), // terra
            line(fres, AppColors.energy, width: 1.2, dash: [5, 4]),
            line(los, AppColors.coverage, width: 2),
          ],
        )),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 16, runSpacing: 6, children: const [
        _Key(Color(0xFFB08968), 'Terreno (com curvatura da Terra)'),
        _Key(AppColors.coverage, 'Linha de visada'),
        _Key(AppColors.energy, 'Limite de 60% da zona de Fresnel'),
      ]),
      const SizedBox(height: 8),
      Text('Distância do enlace: ${profile.distanceKm.toStringAsFixed(2)} km'
          '${profile.dataMissing > 0 ? '  ·  ${profile.dataMissing} ponto(s) sem dado de relevo foram estimados pelo vizinho' : ''}',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
    ]);
  }
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.label);
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
      ]);
}
