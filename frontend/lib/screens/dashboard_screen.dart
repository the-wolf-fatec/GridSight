import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/kpi_card.dart';
import '../widgets/manual_asset_form_modal.dart';
import '../widgets/manual_candidate_form_modal.dart';
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
    ];

    return SafeArea(
      child: LayoutBuilder(builder: (context, cts) {
        final wide = cts.maxWidth > 900;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: SectionTitle(title: 'Painel Geral')),
              OutlinedButton.icon(onPressed: canAdd ? () => openManualCandidateForm(context, app) : null, icon: const Icon(Icons.add_location_alt_outlined, size: 18), label: const Text('Novo candidato')),
              const SizedBox(width: 10),
              OutlinedButton.icon(onPressed: canAdd ? () => openManualAssetForm(context, app) : null, icon: const Icon(Icons.add, size: 18), label: const Text('Novo ativo')),
            ]),
            const SizedBox(height: 12),
            _statusBanner(app),
            const SizedBox(height: 20),
            GridView.count(
              crossAxisCount: wide ? 4 : (cts.maxWidth > 560 ? 2 : 1),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: wide ? 1.5 : 1.7,
              children: [for (final (l, v, i, a) in kpis) KpiCard(label: l, value: v, icon: i, accent: a)],
            ),
          ]),
        );
      }),
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
