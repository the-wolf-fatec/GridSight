import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

typedef ManualFormSubmit = Future<void> Function({
  required String name,
  required String type,
  required double latitude,
  required double longitude,
});

/// Modal genérico de criação manual (nome, tipo, latitude, longitude),
/// compartilhado entre "Novo ativo de rede" e "Novo local candidato" — os
/// dois formulários são idênticos, só muda o texto e pra onde os dados vão.
Future<void> showManualFormModal({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<String> typeOptions,
  required String Function(String) typeLabel,
  required ManualFormSubmit onSubmit,
  required String Function(String name) successMessage,
}) {
  return showDialog(
    context: context,
    builder: (_) => _ManualFormModal(
      title: title,
      subtitle: subtitle,
      typeOptions: typeOptions,
      typeLabel: typeLabel,
      onSubmit: onSubmit,
      successMessage: successMessage,
    ),
  );
}

class _ManualFormModal extends StatefulWidget {
  final String title, subtitle;
  final List<String> typeOptions;
  final String Function(String) typeLabel;
  final ManualFormSubmit onSubmit;
  final String Function(String) successMessage;

  const _ManualFormModal({
    required this.title,
    required this.subtitle,
    required this.typeOptions,
    required this.typeLabel,
    required this.onSubmit,
    required this.successMessage,
  });

  @override
  State<_ManualFormModal> createState() => _ManualFormModalState();
}

class _ManualFormModalState extends State<_ManualFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  late String _type = widget.typeOptions.first;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Nome'),
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [for (final t in widget.typeOptions) DropdownMenuItem(value: t, child: Text(widget.typeLabel(t)))],
                onChanged: _saving ? null : (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _latController,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    validator: (v) => _validateCoordinate(v, 90),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lonController,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    validator: (v) => _validateCoordinate(v, 180),
                  ),
                ),
              ]),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.alert.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.alert.withOpacity(0.4)),
                  ),
                  child: Text('Não foi possível salvar no backend: $_errorMessage', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
              : const Text('Adicionar'),
        ),
      ],
    );
  }

  String? _validateCoordinate(String? v, double limit) {
    if (v == null || v.trim().isEmpty) return 'Obrigatório';
    final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
    if (parsed == null) return 'Número inválido';
    if (parsed < -limit || parsed > limit) return 'Deve estar entre -$limit e $limit';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    try {
      await widget.onSubmit(
        name: name,
        type: _type,
        latitude: double.parse(_latController.text.trim().replaceAll(',', '.')),
        longitude: double.parse(_lonController.text.trim().replaceAll(',', '.')),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.successMessage(name))));
    } catch (e) {
      setState(() {
        _saving = false;
        _errorMessage = e.toString();
      });
    }
  }
}
