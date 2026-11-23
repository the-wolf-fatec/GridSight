import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/scenario_result.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/pdf_button.dart';
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

    return PageBody(
      maxWidth: 1000,
      builder: (context, w) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle(
            title: 'Comparação de Cenários',
            actions: [
              TextButton.icon(
                onPressed: () => _confirm('Apagar todos os cenários?', 'Os ${history.length} cenários do histórico serão removidos permanentemente. Essa ação não pode ser desfeita.', 'Apagar tudo', app.clearAllScenarios),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppColors.alert),
                label: const Text('Apagar tudo', style: TextStyle(color: AppColors.alert)),
              ),
            ],
          ),
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
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          _compareTable(history),
          const SizedBox(height: 20),
          const Text('Detalhamento dos cenários', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          for (final r in history.toList().reversed)
            _scenarioCard(context, app, r, () => _confirm('Apagar cenário?', 'O cenário "${r.label}" será removido da comparação. Essa ação não pode ser desfeita.', 'Apagar', () => app.removeScenario(r.id))),
      ]),
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

/// Tabela lado a lado para comparar os cenários de uma vez (rola para o lado em tela estreita).
Widget _compareTable(List<ScenarioResult> history) {
  const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
  const cellStyle = TextStyle(fontSize: 12.5);
  final bestCoverage = history.map((r) => r.coveragePercent).reduce((a, b) => a > b ? a : b);
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Comparação lado a lado', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 4),
        const Text('Em destaque: maior cobertura.', style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 44,
            columnSpacing: 22,
            columns: const [
              DataColumn(label: Text('Cenário', style: head)),
              DataColumn(label: Text('Cobertura', style: head)),
              DataColumn(label: Text('Gateways', style: head)),
              DataColumn(label: Text('Descobertos', style: head)),
              DataColumn(label: Text('Sem reserva', style: head)),
              DataColumn(label: Text('Relevo', style: head)),
            ],
            rows: [
              for (var i = 0; i < history.length; i++)
                DataRow(cells: [
                  DataCell(Text('C${i + 1} · ${history[i].label}', style: cellStyle)),
                  DataCell(Text('${(history[i].coveragePercent * 100).toStringAsFixed(1)}%', style: cellStyle.copyWith(fontWeight: history[i].coveragePercent == bestCoverage ? FontWeight.w800 : FontWeight.w400, color: history[i].coveragePercent == bestCoverage ? AppColors.coverage : null))),
                  DataCell(Text('${history[i].gatewaysUsed}', style: cellStyle)),
                  DataCell(Text('${history[i].totalAssets - history[i].coveredAssets}', style: cellStyle)),
                  DataCell(Text(history[i].terrain == null ? '-' : '${history[i].terrain!.singlePointCount}', style: cellStyle)),
                  DataCell(Text(history[i].params.useTerrain ? 'sim' : 'não', style: cellStyle)),
                ]),
            ],
          ),
        ),
      ]),
    ),
  );
}

Widget _scenarioCard(BuildContext context, AppState app, ScenarioResult r, VoidCallback onDelete) => _ScenarioCard(result: r, onDelete: onDelete);

/// Cartão de um cenário: fechado mostra só uma linha (nome, cobertura, gateways, descobertos);
/// ao tocar abre com TUDO dentro (números, parâmetros, relevo, gateways e as ações).
class _ScenarioCard extends StatefulWidget {
  const _ScenarioCard({required this.result, required this.onDelete});
  final ScenarioResult result;
  final VoidCallback onDelete;

  @override
  State<_ScenarioCard> createState() => _ScenarioCardState();
}

class _ScenarioCardState extends State<_ScenarioCard> {
  bool _open = false;

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%'.replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final app = context.read<AppState>();
    final t = r.terrain;
    final naoCobertos = r.totalAssets - r.coveredAssets;

    final numeros = <(String, String)>[
      ('Ativos', '${r.totalAssets}'),
      ('Cobertos', '${r.coveredAssets}'),
      ('Não cobertos', '$naoCobertos'),
      ('Gateways usados', '${r.gatewaysUsed}'),
      if (app.candidateSites.isNotEmpty) ('Locais candidatos (dados carregados agora)', '${app.candidateSites.length}'),
      if (t != null) ('Sem reserva (1 gateway só)', '${t.singlePointCount}'),
      if (t != null) ('Perdidos por relevo', '${t.lostToTerrainIds.length}'),
      if (t != null) ('Com reserva (2+ gateways)', '${t.overlappedAssets}'),
      ('Tempo', '${r.processingTime.inMilliseconds} ms'),
    ];
    final parametros = <(String, String)>[
      ('Alcance ref.', '${r.params.rangeKm.toStringAsFixed(1)} km'),
      ('Potência', '${r.params.transmissionPowerDbm.toStringAsFixed(0)} dBm'),
      ('Alcance efetivo', '${r.params.effectiveRangeKm.toStringAsFixed(2)} km'),
      ('Meta de cobertura', '${(r.params.minCoverageTarget * 100).toStringAsFixed(0)}%'),
      ('Máx. gateways', '${r.params.maxGateways}'),
      ('Relevo', r.params.useTerrain ? 'considerado' : 'não considerado'),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${r.gatewaysUsed} gateway${r.gatewaysUsed == 1 ? '' : 's'} · $naoCobertos descoberto${naoCobertos == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.coverage.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(_pct(r.coveragePercent), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.coverage)),
              ),
            ]),
          ),
        ),
        if (_open) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Resultado', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 22, runSpacing: 10, children: [for (final (l, v) in numeros) _miniStat(l, v)]),
              const SizedBox(height: 16),
              const Text('Parâmetros', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 22, runSpacing: 10, children: [for (final (l, v) in parametros) _miniStat(l, v)]),
              if (r.chosenGateways.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Gateways escolhidos (${r.chosenGateways.length})', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Wrap(
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
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton.icon(
                  onPressed: () {
                    app.openScenario(r);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cenário aberto: veja o mapa e os indicadores.')));
                  },
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Abrir no mapa'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    app.reuseScenarioParams(r);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Parâmetros deste cenário copiados para a aba Parâmetros.')));
                  },
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Usar estes parâmetros'),
                ),
                ScenarioPdfButton(result: r),
                TextButton.icon(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Apagar'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.alert),
                ),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }
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
