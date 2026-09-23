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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ParamSlider(
                      label: 'Alcance de referência',
                      value: p.rangeKm,
                      min: 0.5,
                      max: 8,
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
                      max: 30,
                      unit: 'un.',
                      icon: Icons.router_outlined,
                      divisions: 29,
                      onChanged: (v) => update(p.copyWith(maxGateways: v.round())),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 18, color: AppColors.coverage),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
          Text(
            '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} $unit',
            style: const TextStyle(color: AppColors.energy, fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ]),
        Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ],
    );
  }
}
