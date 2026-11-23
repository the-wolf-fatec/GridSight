import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/scenario_result.dart';
import '../services/scenario_pdf.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Botão "PDF do cenário": visualizar/imprimir ou baixar o relatório.
/// Com [compact] vira só um ícone (para caber nos cartões de cenário).
class ScenarioPdfButton extends StatefulWidget {
  const ScenarioPdfButton({super.key, required this.result, this.compact = false});

  final ScenarioResult result;
  final bool compact;

  @override
  State<ScenarioPdfButton> createState() => _ScenarioPdfButtonState();
}

class _ScenarioPdfButtonState extends State<ScenarioPdfButton> {
  bool _busy = false;

  Future<void> _run(bool download) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final fn = download ? downloadScenarioPdf : printScenarioPdf;
      await fn(
        result: widget.result,
        assets: app.assets,
        distribuidoras: app.selectedDistribuidoras.join(', '),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não consegui gerar o PDF: $e'), backgroundColor: AppColors.alert));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.print_outlined, size: 18),
          onPressed: _busy ? null : () => _run(false),
          child: const Text('Visualizar / imprimir'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.download_outlined, size: 18),
          onPressed: _busy ? null : () => _run(true),
          child: const Text('Baixar PDF'),
        ),
      ],
      builder: (context, controller, child) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        if (widget.compact) {
          return IconButton(
            tooltip: 'PDF do cenário',
            onPressed: _busy ? null : toggle,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined, size: 20),
            color: AppColors.textSecondary,
            splashRadius: 20,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          );
        }
        return OutlinedButton.icon(
          onPressed: _busy ? null : toggle,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('PDF do cenário'),
        );
      },
    );
  }
}
