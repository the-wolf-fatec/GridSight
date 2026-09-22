import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'manual_form_modal.dart';

const kCandidateTypeSuggestions = ['poste', 'subestacao'];

Future<void> openManualCandidateForm(BuildContext context, AppState app) {
  return showManualFormModal(
    context: context,
    title: 'Novo local candidato',
    subtitle: 'Cadastre um poste ou subestação manualmente. Ele entra como opção na próxima otimização, e você também pode marcá-lo como gateway direto no Mapa.',
    typeOptions: kCandidateTypeSuggestions,
    typeLabel: (t) => t == 'poste' ? 'Poste' : 'Subestação',
    onSubmit: ({required name, required type, required latitude, required longitude}) =>
        app.addManualCandidateSite(name: name, type: type, latitude: latitude, longitude: longitude),
    successMessage: (name) => 'Local "$name" salvo no backend e adicionado.',
  );
}
