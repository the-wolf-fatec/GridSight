import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../models/coverage_params.dart';
import '../theme/app_theme.dart';
import '../widgets/section_title.dart';

class ParametersScreen extends StatelessWidget {
  const ParametersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.params;
    void update(CoverageParams next) => app.updateParams(next);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(title: 'Parâmetros de Cobertura'),

            // Atalhos por escala geográfica — em vez de calcular na mão qual
            // alcance faz sentido pra cada tamanho de área, escolhe o botão
            // mais parecido com a região que você está cobrindo agora.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Atalho por escala', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    const Text(
                      'Ajusta alcance, potência e limite de gateways de uma vez, conforme o tamanho da área que você está cobrindo.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      _PresetChip(
                        label: 'Bairro / Cidade pequena',
                        sublabel: '~2,5 km (ex.: SJC, Caçapava)',
                        onTap: () => update(p.copyWith(rangeKm: 2.5, transmissionPowerDbm: 20, maxGateways: 12)),
                      ),
                      _PresetChip(
                        label: 'Região metropolitana',
                        sublabel: '~15 km (ex.: Enel SP, Grande SP)',
                        onTap: () => update(p.copyWith(rangeKm: 15, transmissionPowerDbm: 25, maxGateways: 40)),
                      ),
                      _PresetChip(
                        label: 'Estado inteiro',
                        sublabel: '~40 km (várias distribuidoras juntas)',
                        onTap: () => update(p.copyWith(rangeKm: 40, transmissionPowerDbm: 30, maxGateways: 150)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ParamSlider(
                      label: 'Alcance máximo (referência)',
                      value: p.rangeKm,
                      min: 0.5,
                      // Alargado de 8 pra 60 km — o valor antigo só dava
                      // pra cobrir área do tamanho de uma cidade; estado
                      // inteiro/região metropolitana precisa de bem mais.
                      max: 60,
                      unit: 'km',
                      icon: Icons.settings_input_antenna,
                      onChanged: (v) => update(p.copyWith(rangeKm: v)),
                    ),
                    const SizedBox(height: 22),
                    _ParamSlider(
                      label: 'Potência de transmissão',
                      value: p.transmissionPowerDbm,
                      min: 5,
                      max: 30,
                      unit: 'dBm',
                      icon: Icons.bolt,
                      onChanged: (v) => update(p.copyWith(transmissionPowerDbm: v)),
                    ),
                    const SizedBox(height: 22),
                    _ParamSlider(
                      label: 'Meta de cobertura',
                      value: p.minCoverageTarget * 100,
                      min: 50,
                      max: 100,
                      unit: '%',
                      icon: Icons.flag_outlined,
                      onChanged: (v) => update(p.copyWith(minCoverageTarget: v / 100)),
                    ),
                    const SizedBox(height: 22),
                    _ParamSlider(
                      label: 'Limite máximo de gateways',
                      value: p.maxGateways.toDouble(),
                      min: 1,
                      // Alargado de 30 pra 200 — cobrir um estado inteiro
                      // genuinamente precisa de muito mais que 30 gateways.
                      max: 200,
                      unit: 'un.',
                      icon: Icons.router_outlined,
                      divisions: 199,
                      onChanged: (v) => update(p.copyWith(maxGateways: v.round())),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.terrain, size: 18, color: AppColors.coverage),
                  title: const Text('Relevo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  value: p.useTerrain,
                  onChanged: (v) => update(p.copyWith(useTerrain: v)),
                ),
              ),
            ),
            if (p.useTerrain) _TerrainWarning(app: app),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label, sublabel;
  final VoidCallback onTap;
  const _PresetChip({required this.label, required this.sublabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 190,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 3),
            Text(sublabel, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

class _ParamSlider extends StatelessWidget {
  final String label, unit;
  final double value, min, max;
  final IconData icon;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.icon,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    // Garante que o valor atual não ultrapasse o novo min/max (ex.: se um
    // cenário salvo antigo tinha um valor fora da faixa) — evita o Slider
    // quebrar com um assert de "value deve estar entre min e max".
    final safeValue = value.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 18, color: AppColors.coverage),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          Text(
            '${safeValue.toStringAsFixed(safeValue % 1 == 0 ? 0 : 1)} $unit',
            style: const TextStyle(color: AppColors.energy, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ]),
        Slider(value: safeValue, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ],
    );
  }
}

/// Só aparece quando o relevo NÃO está carregado (o relevo em si fica sempre ligado).
class _TerrainWarning extends StatelessWidget {
  final AppState app;
  const _TerrainWarning({required this.app});

  @override
  Widget build(BuildContext context) {
    final st = app.terrainStatus;
    final backendOn = app.planningApi != null;
    if (!backendOn || (st != null && st.ok)) return const SizedBox.shrink();

    final msg = st == null ? 'Relevo indisponível: o backend não respondeu.' : 'Relevo não encontrado na pasta backend/terrain.';
    const color = AppColors.alert;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.4))),
      child: Row(children: [
        const Icon(Icons.terrain, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary))),
        IconButton(tooltip: 'Procurar de novo', onPressed: app.refreshTerrainStatus, icon: const Icon(Icons.refresh, size: 18)),
      ]),
    );
  }
}
