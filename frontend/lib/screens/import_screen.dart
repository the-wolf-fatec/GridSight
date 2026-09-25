import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/manual_asset_form_modal.dart';
import '../widgets/manual_candidate_form_modal.dart';
import '../widgets/section_title.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      if (app.distribuidoras.isEmpty && !app.loadingDistribuidoras) app.loadDistribuidoras();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle(title: 'Importação de Dados'),
          if (app.dataError != null) _errorBanner(app.dataError!, () => app.loadDistribuidoras()),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Distribuidora / Área Geográfica', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                if (app.loadingDistribuidoras)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String>(
                    value: app.selectedDistribuidora,
                    items: [for (final d in app.distribuidoras) DropdownMenuItem(value: d, child: Text(d))],
                    onChanged: (v) {
                      if (v != null) app.selectDistribuidora(v);
                    },
                  ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: app.loadingData || app.selectedDistribuidora == null ? null : () => app.importData(),
                  icon: app.loadingData ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background)) : const Icon(Icons.cloud_download_outlined),
                  label: Text(app.loadingData ? 'Importando...' : 'Importar dados'),
                ),
                if (app.dataImported) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    const Icon(Icons.check_circle, color: AppColors.coverage, size: 18),
                    const SizedBox(width: 8),
                    Text('Importação concluída para "${app.selectedDistribuidora}".', style: const TextStyle(color: AppColors.coverage, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 20),
          if (app.dataImported)
            LayoutBuilder(builder: (context, cts) {
              final assetsList = _listCard('Ativos da rede (pontos a cobrir)', Icons.sensors, AppColors.primaryLight, true, app.assets.length,
                  _addButton(AppColors.primaryLight, 'Adicionar ativo manualmente', () => openManualAssetForm(context, app)),
                  (i) => _row(app.assets[i].name, '${app.assets[i].type} · ${app.assets[i].latitude.toStringAsFixed(4)}, ${app.assets[i].longitude.toStringAsFixed(4)}'));
              final candidatesList = _listCard('Locais candidatos a gateways', null, AppColors.energy, false, app.candidateSites.length,
                  _addButton(AppColors.energy, 'Adicionar local candidato manualmente', () => openManualCandidateForm(context, app)),
                  (i) => _row(app.candidateSites[i].name, '${app.candidateSites[i].type} · ${app.candidateSites[i].latitude.toStringAsFixed(4)}, ${app.candidateSites[i].longitude.toStringAsFixed(4)}'));

              if (cts.maxWidth > 700) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: assetsList), const SizedBox(width: 16), Expanded(child: candidatesList)]);
              return Column(children: [assetsList, const SizedBox(height: 16), candidatesList]);
            }),
        ]),
      ),
    );
  }
}

Widget _addButton(Color color, String tooltip, VoidCallback onPressed) => IconButton(
      tooltip: tooltip,
      icon: Icon(Icons.add_circle_outline, color: color, size: 20),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );

Widget _errorBanner(String message, VoidCallback onRetry) => Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.alert.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.alert.withOpacity(0.4))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.alert, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Não foi possível falar com o backend', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(message, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ]),
        ),
        TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
      ]),
    );

Widget _listCard(String title, IconData? icon, Color color, bool showIcon, int count, Widget trailing, Widget Function(int) itemBuilder) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (showIcon && icon != null) ...[Icon(icon, color: color, size: 18), const SizedBox(width: 8)],
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            trailing,
          ]),
          const Divider(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.separated(shrinkWrap: true, itemCount: count, separatorBuilder: (_, __) => const Divider(height: 14), itemBuilder: (_, i) => itemBuilder(i)),
          ),
        ]),
      ),
    );

Widget _row(String title, String subtitle) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
    ]);
