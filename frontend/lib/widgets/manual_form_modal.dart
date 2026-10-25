import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

class _PlaceResult {
  final String name;
  final double lat;
  final double lon;
  const _PlaceResult({required this.name, required this.lat, required this.lon});
}

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
  final _placeSearchController = TextEditingController();
  late String _type = widget.typeOptions.first;
  bool _saving = false;
  String? _errorMessage;
  List<_PlaceResult> _placeResults = [];
  bool _searchingPlace = false;
  Timer? _searchDebounce;

  // Mesmo motivo do Mapa: espera parar de digitar antes de buscar, pra não
  // estourar o limite de 1 pedido/segundo do Nominatim.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 600), () => _searchPlace(query));
  }

  Future<void> _searchPlace(String query) async {
    if (query.trim().length < 3) {
      setState(() => _placeResults = []);
      return;
    }
    setState(() => _searchingPlace = true);
    try {
      // Passa pelo backend (proxy) em vez de chamar o Nominatim direto —
      // mesmo motivo da busca do Mapa: o app sozinho não consegue (CORS
      // no Web, bloqueio de rede no Android).
      final app = context.read<AppState>();
      final base = app.backendBaseUrl ?? 'http://localhost:8080/api';
      final uri = Uri.parse('$base/geocode?q=${Uri.encodeQueryComponent(query)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        setState(() => _placeResults = list.map((e) => _PlaceResult(name: e['display_name'] as String, lat: double.parse(e['lat'] as String), lon: double.parse(e['lon'] as String))).toList());
      }
    } catch (_) {
      // Busca é um complemento — se falhar, a pessoa ainda pode digitar
      // latitude/longitude na mão, então não precisa travar nada aqui.
    }
    setState(() => _searchingPlace = false);
  }

  void _usePlace(_PlaceResult place) {
    setState(() {
      _latController.text = place.lat.toStringAsFixed(6);
      _lonController.text = place.lon.toStringAsFixed(6);
      _placeResults = [];
      _placeSearchController.text = place.name;
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _nameController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _placeSearchController.dispose();
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
              // Busca de local (rua, bairro, cidade — quanto mais
              // específico digitar, mais preciso o resultado) que preenche
              // latitude/longitude sozinho. Continuam editáveis depois,
              // pra ajuste fino manual se precisar.
              TextFormField(
                controller: _placeSearchController,
                enabled: !_saving,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  labelText: 'Buscar local (rua, bairro ou cidade)',
                  hintText: 'Ex.: Rua das Flores, São José dos Campos',
                  suffixIcon: _searchingPlace
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : const Icon(Icons.search, size: 20),
                ),
              ),
              if (_placeResults.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(8)),
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _placeResults.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (context, i) {
                      final r = _placeResults[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined, size: 18),
                        title: Text(r.name, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => _usePlace(r),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 10),
              const Text('Ou ajuste direto (preenche sozinho ao escolher um local acima):', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
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