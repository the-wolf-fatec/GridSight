import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/kpi_card.dart';
import '../widgets/section_title.dart';

class IndicatorsScreen extends StatelessWidget {
  const IndicatorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final result = context.watch<AppState>().currentResult;
    if (result == null) return _emptyState();

    final covered = result.coveragePercent * 100;
    final uncovered = 100 - covered;
    final kpis = [
      ('% de pontos cobertos', '${covered.toStringAsFixed(1)}%', Icons.check_circle_outline, AppColors.coverage),
      ('Gateways utilizados', '${result.gatewaysUsed}', Icons.router_outlined, AppColors.energy),
      ('Ativos não cobertos', '${result.totalAssets - result.coveredAssets}', Icons.report_gmailerrorred_outlined, AppColors.alert),
      ('Tempo de processamento', '${result.processingTime.inMilliseconds} ms', Icons.speed, AppColors.primaryLight),
    ];

    return SafeArea(
      child: LayoutBuilder(builder: (context, cts) {
        final wide = cts.maxWidth > 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle(title: 'Indicadores de Qualidade'),
            GridView.count(
              crossAxisCount: wide ? 4 : (cts.maxWidth > 560 ? 2 : 1),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: wide ? 1.5 : 1.7,
              children: [for (final (l, v, i, a) in kpis) KpiCard(label: l, value: v, icon: i, accent: a)],
            ),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, c) {
              final donut = _chartCard('Cobertura (rosca)', SizedBox(height: 220, child: Row(children: [
                Expanded(child: PieChart(PieChartData(sectionsSpace: 3, centerSpaceRadius: 42, sections: [_pie(covered, AppColors.coverage), _pie(uncovered, AppColors.alert)]))),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: const [_dotLabel(AppColors.coverage, 'Cobertos'), SizedBox(height: 8), _dotLabel(AppColors.alert, 'Não cobertos')]),
              ])));

              final bars = _chartCard('Cobertos vs. não cobertos', SizedBox(height: 220, child: BarChart(BarChartData(
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 8), child: Text(v == 0 ? 'Cobertos' : 'Não cobertos', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))))),
                ),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: result.coveredAssets.toDouble(), color: AppColors.coverage, width: 34, borderRadius: BorderRadius.circular(6))]),
                  BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: (result.totalAssets - result.coveredAssets).toDouble(), color: AppColors.alert, width: 34, borderRadius: BorderRadius.circular(6))]),
                ],
              ))));

              if (c.maxWidth > 760) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: donut), const SizedBox(width: 16), Expanded(child: bars)]);
              return Column(children: [donut, const SizedBox(height: 16), bars]);
            }),
          ]),
        );
      }),
    );
  }
}

PieChartSectionData _pie(double value, Color color) => PieChartSectionData(value: value, color: color, title: value > 4 ? '${value.toStringAsFixed(0)}%' : '', titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.background), radius: 54);

Widget _chartCard(String title, Widget child) => Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), const SizedBox(height: 14), child]),
      ),
    );

class _dotLabel extends StatelessWidget {
  final Color color;
  final String text;
  const _dotLabel(this.color, this.text);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
      ]);
}

Widget _emptyState() => const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insights_outlined, size: 48, color: AppColors.textSecondary),
          SizedBox(height: 14),
          Text('Nenhum resultado disponível', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          SizedBox(height: 6),
          Text('Execute a otimização na aba "Mapa" para gerar os indicadores de qualidade.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      ),
    );
