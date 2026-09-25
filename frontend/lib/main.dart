import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'state/app_state.dart';
import 'services/data_repository.dart';
import 'services/mock_data_repository.dart';
import 'services/api_data_repository.dart';
import 'services/scenario_api_service.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';

/// --- Configuração de integração com o backend ---
///
/// [useBackend] é a chave principal:
/// - `true`  → o app fala de verdade com o Spring Boot em [backendBaseUrl]
///             (importação de dados via MySQL + histórico de cenários
///             persistido no banco).
/// - `false` → o app roda 100% offline com dados simulados em memória
///             (útil pra demonstrar a interface sem precisar do backend
///             rodando, ex.: numa apresentação).
const bool useBackend = true;

/// Endereço do backend Spring Boot — detectado sozinho conforme onde o app
/// está rodando, pra não precisar trocar essa linha toda vez que você troca
/// de VS Code/Chrome pro emulador Android e vice-versa:
///
/// - Emulador Android → 10.0.2.2 (alias do emulador para a máquina host)
/// - Web (Chrome/Edge), Windows/macOS/Linux desktop → localhost
///
/// Não cobre celular físico — nesse caso ainda é preciso trocar na mão pelo
/// IP da sua máquina na rede Wi-Fi (ex.: 192.168.0.15), porque não tem como
/// detectar isso automaticamente.
String get _backendHost {
  if (kIsWeb) return 'localhost';
  try {
    if (Platform.isAndroid) return '10.0.2.2';
  } catch (_) {
    // Platform pode não estar disponível em alguns contextos; localhost cobre o resto.
  }
  return 'localhost';
}

final String backendBaseUrl = 'http://$_backendHost:8080/api';

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

    return ChangeNotifierProvider(
      create: (_) {
        final state = AppState(
          repository,
          scenarioApi: scenarioApi,
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
