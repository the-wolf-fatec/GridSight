import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/kpi_card.dart';
import '../widgets/manual_asset_form_modal.dart';
import '../widgets/manual_candidate_form_modal.dart';
import '../widgets/pdf_button.dart';
import 'import_screen.dart' show distribuidoraColor;
import '../widgets/section_title.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final result = app.currentResult;
    final canAdd = app.selectedDistribuidora != null;
    final kpis = [
      ('Ativos carregados', '${app.assets.length}', Icons.sensors, AppColors.primaryLight),
      ('Locais candidatos', '${app.candidateSites.length}', Icons.location_on_outlined, AppColors.energy),
      ('Cobertura obtida', result == null ? '—' : '${(result.coveragePercent * 100).toStringAsFixed(1)}%', Icons.wifi_tethering, AppColors.coverage),
      ('Gateways utilizados', result == null ? '—' : '${result.gatewaysUsed}', Icons.router_outlined, AppColors.alert),
      ('Distribuidoras no mapa', '${_distribuidoraRows(app).length}', Icons.business_outlined, AppColors.primaryLight),
      ('Cenários no histórico', '${app.scenarioHistory.length}', Icons.history, AppColors.textSecondary),
      ('Ativos sem reserva', result?.terrain == null ? '—' : '${result!.terrain!.singlePointCount}', Icons.shield_outlined, AppColors.energy),
    ];

    return PageBody(
      builder: (context, w) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Título SEMPRE em cima, na horizontal; os botões ficam logo abaixo
        // e quebram de linha sozinhos se a tela for estreita.
        const SectionTitle(title: 'Painel Geral'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              style: compactOutlined(),
              onPressed: canAdd ? () => openManualCandidateForm(context, app) : null,
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Novo candidato'),
            ),
            OutlinedButton.icon(
              style: compactOutlined(),
              onPressed: canAdd ? () => openManualAssetForm(context, app) : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Novo ativo'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _statusBanner(app),
        const SizedBox(height: 16),
        ResponsiveGrid(
          children: [for (final (l, v, i, a) in kpis) KpiCard(label: l, value: v, icon: i, accent: a)],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final left = _distribuidorasCard(app);
          final right = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _typesCard('Tipos de ativo no mapa', _countBy(app.assets.map((a) => a.type))),
            const SizedBox(height: 16),
            _typesCard('Tipos de local candidato', _countBy(app.candidateSites.map((c) => c.type))),
            const SizedBox(height: 16),
            _statusCard(app),
          ]);
          if (c.maxWidth > 820) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: left), const SizedBox(width: 16), Expanded(flex: 2, child: right)]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: 16), right]);
        }),
      ]),
    );
  }
}

Widget _statusBanner(AppState app) {
  final (message, color, icon) = !app.dataImported
      ? ('Comece importando os dados da BDGD na aba "Importação de Dados".', AppColors.energy, Icons.info_outline)
      : app.currentResult == null
          ? ('Dados importados. Ajuste os parâmetros e execute a otimização.', AppColors.primaryLight, Icons.tune)
          : ('Cenário executado com sucesso. Confira o mapa e os indicadores.', AppColors.coverage, Icons.check_circle_outline);

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.4))),
    child: Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 12), Expanded(child: Text(message, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5)))]),
  );
}


// ---------- Cartões do painel ----------

Widget _panelCard(String title, Widget child, {Widget? trailing}) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );

class _DistRow {
  final String name;
  final int assets;
  final int candidates;
  final int? covered; // null = ainda sem cenário
  const _DistRow(this.name, this.assets, this.candidates, this.covered);
}

List<_DistRow> _distribuidoraRows(AppState app) {
  final terrain = app.currentResult?.terrain;
  final assetCount = <String, int>{};
  final coveredCount = <String, int>{};
  for (final a in app.assets) {
    final d = a.distribuidora.isEmpty ? 'Sem distribuidora' : a.distribuidora;
    assetCount[d] = (assetCount[d] ?? 0) + 1;
    if (terrain != null && terrain.isCovered(a.id)) coveredCount[d] = (coveredCount[d] ?? 0) + 1;
  }
  final candCount = <String, int>{for (final e in app.candidateSitesByDistribuidora.entries) e.key: e.value.length};
  final names = <String>{...assetCount.keys, ...candCount.keys}.toList()..sort();
  return [for (final n in names) _DistRow(n, assetCount[n] ?? 0, candCount[n] ?? 0, terrain == null ? null : (coveredCount[n] ?? 0))];
}

Widget _distribuidorasCard(AppState app) {
  final rows = _distribuidoraRows(app);
  if (rows.isEmpty) {
    return _panelCard('Distribuidoras no mapa', const Text('Nenhuma distribuidora carregada. Use a aba "Importação de Dados" para escolher uma ou mais.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)));
  }
  final maxAssets = rows.map((r) => r.assets).fold<int>(1, (a, b) => b > a ? b : a);
  return _panelCard(
    'Distribuidoras no mapa',
    Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: distribuidoraColor(r.name), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Text(
                r.covered == null ? '${r.assets} ativos · ${r.candidates} candidatos' : '${r.covered}/${r.assets} cobertos · ${r.candidates} candidatos',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: r.covered == null ? (r.assets / maxAssets) : (r.assets == 0 ? 0 : r.covered! / r.assets),
                minHeight: 7,
                backgroundColor: AppColors.divider,
                color: r.covered == null ? distribuidoraColor(r.name) : AppColors.coverage,
              ),
            ),
          ]),
        ),
    ]),
    trailing: Text(app.currentResult?.terrain == null ? 'barra = tamanho' : 'barra = cobertura', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
  );
}

List<MapEntry<String, int>> _countBy(Iterable<String> items) {
  final m = <String, int>{};
  for (final i in items) {
    final k = i.isEmpty ? 'Sem tipo' : i;
    m[k] = (m[k] ?? 0) + 1;
  }
  final out = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return out;
}

Widget _typesCard(String title, List<MapEntry<String, int>> counts) {
  return _panelCard(
    title,
    counts.isEmpty
        ? const Text('Nada carregado ainda.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
        : Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in counts.take(10))
              Chip(
                label: Text('${e.key}  ${e.value}', style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ]),
  );
}

Widget _statusCard(AppState app) {
  final r = app.currentResult;
  final ts = app.terrainStatus;
  Widget line(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ]),
      );
  return _panelCard(
    'Situação do sistema',
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (ts == null)
        line(Icons.cloud_off_outlined, AppColors.textSecondary, 'Backend de relevo não consultado (modo offline ou ainda carregando).')
      else if (ts.ok)
        line(Icons.terrain, AppColors.coverage, 'Relevo: ${ts.tileCount} arquivo(s) .hgt encontrados.')
      else
        line(Icons.warning_amber_rounded, AppColors.energy, 'Relevo: nenhum arquivo .hgt encontrado. ${ts.hint}'),
      if (r == null)
        line(Icons.info_outline, AppColors.textSecondary, 'Nenhum cenário executado ainda.')
      else ...[
        line(Icons.check_circle_outline, AppColors.coverage, 'Último cenário: ${r.label} (${(r.coveragePercent * 100).toStringAsFixed(1)}% de cobertura, ${r.gatewaysUsed} gateways).'),
        if (r.terrain != null)
          line(Icons.shield_outlined, r.terrain!.singlePointCount == 0 ? AppColors.coverage : AppColors.energy,
              'Segurança: ${r.terrain!.protectedCount} ativos com reserva e ${r.terrain!.singlePointCount} sem reserva.'),
        const SizedBox(height: 8),
        ScenarioPdfButton(result: r),
      ],
    ]),
  );
}
