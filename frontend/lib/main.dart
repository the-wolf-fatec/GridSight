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

/// Endereço do backend Spring Boot.
///
/// Por padrão é `http://localhost:8080/api` (serve para o Chrome e para o Windows).
/// Para trocar SEM mexer no código, passe o endereço na hora de rodar:
///
///   flutter run -d <id> --dart-define=BACKEND_URL=http://192.168.0.15:8080/api
///
/// Celular Android ligado por cabo USB: o jeito mais simples é deixar `localhost` e rodar,
/// no computador, `adb reverse tcp:8080 tcp:8080` — assim o `localhost` do celular
/// aponta para o backend do computador (sem precisar de Wi-Fi nem de IP).
/// Emulador Android: use `--dart-define=BACKEND_URL=http://10.0.2.2:8080/api`.
const String backendBaseUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080/api',
);

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
        // Limita o tamanho de fonte do sistema (alguns celulares usam fonte
        // grande demais e quebram o layout): entre 90% e 115%.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: Consumer<AppState>(
          builder: (context, app, _) => app.isAuthenticated ? const HomeShell() : const LoginScreen(),
        ),
      ),
    );
  }
}
