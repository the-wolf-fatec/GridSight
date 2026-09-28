import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Cartão de indicador (número + rótulo), usado no Painel e em Indicadores.
///
/// O parâmetro [icon] continua existindo só por compatibilidade com quem já
/// chama este widget passando um ícone — ele não é mais desenhado, pra
/// manter os cards limpos (só número + texto, sem decoração).
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon; // aceito, mas ignorado de propósito
  final Color accent;
  final String? subtitle;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent = AppColors.coverage,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: accent),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}