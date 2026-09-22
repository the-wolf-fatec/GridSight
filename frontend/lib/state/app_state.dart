import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/candidate_site.dart';
import '../models/coverage_params.dart';
import '../models/scenario_result.dart';
import '../services/data_repository.dart';
import '../services/optimization_service.dart';
import '../services/scenario_api_service.dart';

/// Estado central da aplicação: dados carregados, parâmetros de cobertura
/// e histórico de cenários. [scenarioApi] é opcional — sem ele o histórico
/// fica só em memória.
class AppState extends ChangeNotifier {
  AppState(this._repository, {this.scenarioApi, this.backendBaseUrl});

  final DataRepository _repository;
  final OptimizationService _optimizationService = OptimizationService();
  final ScenarioApiService? scenarioApi;

  // Endereço base do backend, usado pelo Mapa pra buscar tiles via proxy
  // (TileProxyController). Null no modo mock/offline.
  final String? backendBaseUrl;

  // --- Autenticação (login simples, credenciais fixas, sem backend de usuários) ---
  static const String _adminUser = 'admin';
  static const String _adminPassword = 'gridsight123';

  bool isAuthenticated = false;
  String? loginError;

  bool login(String username, String password) {
    final ok = username.trim() == _adminUser && password == _adminPassword;
    isAuthenticated = ok;
    loginError = ok ? null : 'Usuário ou senha inválidos.';
    notifyListeners();
    return ok;
  }

  void logout() {
    isAuthenticated = false;
    notifyListeners();
  }

  // --- Distribuidoras / dataset ativo ---
  List<String> distribuidoras = [];
  String? selectedDistribuidora;
  bool loadingDistribuidoras = false;

  // --- Dados importados ---
  List<Asset> assets = [];
  List<CandidateSite> candidateSites = [];
  bool loadingData = false;
  bool dataImported = false;

  // --- Parâmetros de cobertura de RF ---
  CoverageParams params = const CoverageParams();

  // --- Otimização ---
  bool running = false;
  ScenarioResult? currentResult;

  // --- Comparação de cenários ---
  final List<ScenarioResult> scenarioHistory = [];
  bool _scenarioHistoryLoaded = false;
  bool loadingScenarioHistory = false;

  String? lastSyncError; // erro ao sincronizar cenários com o backend
  String? dataError; // erro ao carregar distribuidoras/dados

  Future<void> loadDistribuidoras() async {
    loadingDistribuidoras = true;
    dataError = null;
    notifyListeners();
    try {
      distribuidoras = await _repository.fetchDistribuidoras();
      selectedDistribuidora ??= distribuidoras.isNotEmpty ? distribuidoras.first : null;
    } catch (e) {
      dataError = e.toString();
    }
    loadingDistribuidoras = false;
    notifyListeners();
  }

  // Chamado uma vez ao iniciar o app. Depois de um F5 o estado em memória
  // some — em vez de reimportar tudo sozinho, restaura só o que foi
  // criado manualmente (ativos/candidatos); o resto exige "Importar dados".
  Future<void> bootstrap() async {
    await loadDistribuidoras();
    try {
      final manualAssets = await _repository.fetchManualAssets();
      final manualCandidates = await _repository.fetchManualCandidateSites();
      if (manualAssets.isNotEmpty || manualCandidates.isNotEmpty) {
        assets = manualAssets;
        candidateSites = manualCandidates;
        if (manualAssets.isNotEmpty) selectedDistribuidora = manualAssets.first.distribuidora;
        dataImported = true;
        notifyListeners();
      }
    } catch (e) {
      dataError = e.toString();
      notifyListeners();
    }
  }

  Future<void> selectDistribuidora(String distribuidora) async {
    selectedDistribuidora = distribuidora;
    dataImported = false;
    assets = [];
    candidateSites = [];
    currentResult = null;
    notifyListeners();
  }

  Future<void> importData() async {
    if (selectedDistribuidora == null) return;
    loadingData = true;
    dataError = null;
    notifyListeners();

    try {
      assets = await _repository.fetchAssets(selectedDistribuidora!);
      candidateSites = await _repository.fetchCandidateSites(selectedDistribuidora!);
      dataImported = true;
    } catch (e) {
      dataError = e.toString();
      dataImported = false;
    }

    loadingData = false;
    notifyListeners();
  }

  void updateParams(CoverageParams newParams) {
    params = newParams;
    notifyListeners();
  }

  // Salva no backend antes de entrar em [assets], pra não ficar fora de
  // sincronia com o banco se a gravação falhar.
  Future<void> addManualAsset({required String name, required String type, required double latitude, required double longitude}) async {
    final draft = Asset(
      id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      latitude: latitude,
      longitude: longitude,
      distribuidora: selectedDistribuidora ?? '',
    );
    final saved = await _repository.createAsset(draft);
    assets = [...assets, saved];
    notifyListeners();
  }

  Future<void> addManualCandidateSite({required String name, required String type, required double latitude, required double longitude}) async {
    final draft = CandidateSite(id: 'temp-${DateTime.now().microsecondsSinceEpoch}', name: name, type: type, latitude: latitude, longitude: longitude);
    final saved = await _repository.createCandidateSite(draft, selectedDistribuidora ?? '');
    candidateSites = [...candidateSites, saved];
    notifyListeners();
  }

  // Marca/desmarca um local candidato como gateway direto no mapa, sem
  // depender do algoritmo. Só afeta [currentResult] — não vira um cenário
  // salvo no histórico/backend (isso só acontece via runOptimization).
  void toggleManualGateway(CandidateSite site) {
    final existing = currentResult;
    final base = existing?.chosenGateways ?? const <CandidateSite>[];
    final chosen = base.any((g) => g.id == site.id);
    final newGateways = chosen ? base.where((g) => g.id != site.id).toList() : [...base, site];

    final coveredCount = _optimizationService
        .coveredAssetIndexes(assets: assets, gateways: newGateways, rangeKm: params.effectiveRangeKm)
        .length;

    currentResult = ScenarioResult(
      id: existing?.id ?? 'manual-${DateTime.now().microsecondsSinceEpoch}',
      label: existing?.label ?? 'Ajuste manual',
      executedAt: existing?.executedAt ?? DateTime.now(),
      params: existing?.params ?? params,
      chosenGateways: newGateways,
      totalAssets: assets.length,
      coveredAssets: coveredCount,
      processingTime: existing?.processingTime ?? Duration.zero,
    );
    notifyListeners();
  }

  Future<void> loadScenarioHistoryIfNeeded() async {
    if (_scenarioHistoryLoaded || scenarioApi == null) return;
    _scenarioHistoryLoaded = true;
    loadingScenarioHistory = true;
    notifyListeners();

    try {
      // Backend devolve mais recente primeiro; guardamos invertido pra
      // bater com a ordem de runOptimization.
      final remote = await scenarioApi!.fetchScenarios();
      scenarioHistory
        ..clear()
        ..addAll(remote.reversed);
      if (scenarioHistory.isNotEmpty) currentResult = scenarioHistory.last;
      lastSyncError = null;
    } catch (e) {
      lastSyncError = e.toString();
    }

    loadingScenarioHistory = false;
    notifyListeners();
  }

  Future<void> runOptimization({String? label}) async {
    if (assets.isEmpty || candidateSites.isEmpty) return;
    running = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 700));

    var result = _optimizationService.run(
      label: label ?? 'Cenário ${scenarioHistory.length + 1}',
      assets: assets,
      candidates: candidateSites,
      params: params,
    );

    if (scenarioApi != null && selectedDistribuidora != null) {
      try {
        result = await scenarioApi!.createScenario(local: result, distribuidora: selectedDistribuidora!);
        lastSyncError = null;
      } catch (e) {
        lastSyncError = e.toString();
      }
    }

    currentResult = result;
    scenarioHistory.add(result);
    running = false;
    notifyListeners();
  }

  Future<void> removeScenario(String id) async {
    if (scenarioApi != null) await scenarioApi!.deleteScenario(id);
    scenarioHistory.removeWhere((s) => s.id == id);
    if (currentResult?.id == id) {
      currentResult = scenarioHistory.isNotEmpty ? scenarioHistory.last : null;
    }
    notifyListeners();
  }

  Future<void> clearAllScenarios() async {
    if (scenarioApi != null) await scenarioApi!.deleteAllScenarios();
    scenarioHistory.clear();
    currentResult = null;
    notifyListeners();
  }
}
