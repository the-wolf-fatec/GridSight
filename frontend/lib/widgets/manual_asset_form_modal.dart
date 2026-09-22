import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'manual_form_modal.dart';

const kAssetTypeSuggestions = ['Sensor de Corrente', 'Medidor Inteligente', 'Chave Telecomandada', 'Religador'];

Future<void> openManualAssetForm(BuildContext context, AppState app) {
  return showManualFormModal(
    context: context,
    title: 'Novo ativo de rede',
    subtitle: 'Cadastre um ativo manualmente. Ele é salvo no backend e passa a valer na próxima otimização executada.',
    typeOptions: kAssetTypeSuggestions,
    typeLabel: (t) => t,
    onSubmit: ({required name, required type, required latitude, required longitude}) =>
        app.addManualAsset(name: name, type: type, latitude: latitude, longitude: longitude),
    successMessage: (name) => 'Ativo "$name" salvo no backend e adicionado.',
  );
}
