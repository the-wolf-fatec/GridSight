import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/scenario_result.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/section_title.dart';

class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key});
  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().loadScenarioHistoryIfNeeded());
  }

  void _confirm(String title, String content, String label, Future<void> Function() action) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.alert),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await action();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível apagar no backend: $e'), backgroundColor: AppColors.alert));
              }
            },
            child: Text(label),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final history = app.scenarioHistory;

    if (app.loadingScenarioHistory && history.isEmpty) return const Center(child: CircularProgressIndicator());
    if (history.isEmpty) return _emptyState(app.scenarioApi != null ? app.lastSyncError : null);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: SectionTitle(title: 'Comparação de Cenários')),
            TextButton.icon(
              onPressed: () => _confirm('Apagar todos os cenários?', 'Os ${history.length} cenários do histórico serão removidos permanentemente. Essa ação não pode ser desfeita.', 'Apagar tudo', app.clearAllScenarios),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppColors.alert),
              label: const Text('Apagar tudo', style: TextStyle(color: AppColors.alert)),
            ),
          ]),
          if (app.scenarioApi != null && app.lastSyncError != null) _syncErrorBanner(app.lastSyncError!),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cobertura por cenário (%)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 16),
                SizedBox(height: 220, child: _coverageChart(history)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Detalhamento dos cenários', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          for (final r in history.toList().reversed)
            _scenarioCard(r, () => _confirm('Apagar cenário?', 'O cenário "${r.label}" será removido da comparação. Essa ação não pode ser desfeita.', 'Apagar', () => app.removeScenario(r.id))),
        ]),
      ),
    );
  }
}

Widget _coverageChart(List<ScenarioResult> history) => BarChart(BarChartData(
      maxY: 100,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 8), child: Text('C${idx + 1}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)));
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < history.length; i++)
          BarChartGroupData(x: i, barRods: [BarChartRodData(toY: history[i].coveragePercent * 100, color: i == history.length - 1 ? AppColors.energy : AppColors.coverage, width: 26, borderRadius: BorderRadius.circular(6))]),
      ],
    ));

Widget _syncErrorBanner(String message) => Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.alert.withOpacity(0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.alert.withOpacity(0.4))),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.alert),
        const SizedBox(width: 10),
        Expanded(child: Text('Não foi possível sincronizar com o backend — mostrando dados locais. ($message)', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
      ]),
    );

Widget _scenarioCard(ScenarioResult r, VoidCallback onDelete) {
  final stats = <(String, String)>[
    ('Ativos cobertos', '${r.coveredAssets} / ${r.totalAssets}'),
    ('Ativos não cobertos', '${r.totalAssets - r.coveredAssets}'),
    ('Gateways usados', '${r.gatewaysUsed}'),
    ('Alcance ref.', '${r.params.rangeKm.toStringAsFixed(1)} km'),
    ('Potência', '${r.params.transmissionPowerDbm.toStringAsFixed(0)} dBm'),
    ('Alcance efetivo', '${r.params.effectiveRangeKm.toStringAsFixed(2)} km'),
    ('Meta', '${(r.params.minCoverageTarget * 100).toStringAsFixed(0)}%'),
    ('Máx. gateways', '${r.params.maxGateways}'),
    ('Tempo', '${r.processingTime.inMilliseconds} ms'),
  ];

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.coverage.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Text('${(r.coveragePercent * 100).toStringAsFixed(1)}% cobertura', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.coverage)),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 20), color: AppColors.textSecondary, tooltip: 'Apagar cenário', splashRadius: 20, constraints: const BoxConstraints(), padding: EdgeInsets.zero),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 20, runSpacing: 10, children: [for (final (l, v) in stats) _miniStat(l, v)]),
        if (r.chosenGateways.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          const Text('Gateways escolhidos', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in r.chosenGateways)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.energy.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.energy.withOpacity(0.35))),
                  child: Text(g.name, style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary)),
                ),
            ],
          ),
        ],
      ]),
    ),
  );
}

Widget _miniStat(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ],
    );

Widget _emptyState(String? syncError) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bar_chart_outlined, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 14),
          const Text('Nenhum cenário para comparar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Execute ao menos dois cenários na aba "Mapa" (variando os parâmetros) para compará-los aqui.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          if (syncError != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.alert.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Text('Backend indisponível ($syncError) — histórico local vazio.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppColors.alert)),
            ),
          ],
        ]),
      ),
    );
