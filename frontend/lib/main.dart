import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'state/app_state.dart';
import 'services/data_repository.dart';
import 'services/mock_data_repository.dart';
import 'services/api_data_repository.dart';
import 'services/scenario_api_service.dart';
import 'services/planning_api_service.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

/// --- Configuração de integração com o backend ---
///
/// [useBackend] é a ÚNICA chave que você precisa mexer:
/// - `true`  → o app fala de verdade com o Spring Boot em [backendBaseUrl]
///             (importação de dados via MySQL + histórico de cenários
///             persistido no banco).
/// - `false` → o app roda 100% offline com dados simulados em memória
///             (útil pra demonstrar a interface sem precisar do backend
///             rodando, ex.: numa apresentação).
const bool useBackend = true;

/// Endereço do backend Spring Boot. Se for testar em um emulador Android,
/// troque 'localhost' por '10.0.2.2' (o alias padrão do emulador para a
/// máquina host). Em um dispositivo físico, use o IP da máquina na rede.
const String backendBaseUrl = 'http://localhost:8080/api';

void main() {
  runApp(const GridSightApp());
}

class GridSightApp extends StatelessWidget {
  const GridSightApp({super.key});

  @override
  Widget build(BuildContext context) {
    final DataRepository repository = useBackend
        ? ApiDataRepository(baseUrl: backendBaseUrl)
        : MockDataRepository();

    final ScenarioApiService? scenarioApi =
        useBackend ? ScenarioApiService(baseUrl: backendBaseUrl) : null;

    final PlanningApiService? planningApi =
        useBackend ? PlanningApiService(baseUrl: backendBaseUrl) : null;

    return ChangeNotifierProvider(
      create: (_) {
        final state = AppState(
          repository,
          scenarioApi: scenarioApi,
          planningApi: planningApi,
          backendBaseUrl: useBackend ? backendBaseUrl : null,
        );
        state.bootstrap(); // carrega distribuidora + dados automaticamente ao iniciar/F5
        return state;
      },
      child: MaterialApp(
        title: 'GridSight',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: Consumer<AppState>(
          builder: (context, app, _) => app.isAuthenticated ? const HomeShell() : const LoginScreen(),
        ),
      ),
    );
  }
}
