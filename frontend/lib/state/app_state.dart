import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/candidate_site.dart';
import '../models/coverage_params.dart';
import '../models/scenario_result.dart';
import '../models/terrain_analysis.dart';
import '../services/data_repository.dart';
import '../services/optimization_service.dart';
import '../services/planning_api_service.dart';
import '../services/scenario_api_service.dart';

/// Estado central da aplicação: dados carregados, parâmetros de cobertura
/// e histórico de cenários. [scenarioApi] é opcional — sem ele o histórico
/// fica só em memória.
class AppState extends ChangeNotifier {
  AppState(this._repository, {this.scenarioApi, this.planningApi, this.backendBaseUrl});

  final DataRepository _repository;
  final OptimizationService _optimizationService = OptimizationService();
  final ScenarioApiService? scenarioApi;
  // Planejamento com relevo (backend lê os .hgt). Null no modo mock/offline.
  final PlanningApiService? planningApi;

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
  String? selectedDistribuidora; // mantido pra criação manual de ativo/candidato (usa a 1ª marcada)
  Set<String> selectedDistribuidoras = {}; // seleção múltipla — permite ver várias juntas no mapa
  bool loadingDistribuidoras = false;

  void toggleDistribuidoraSelection(String d) {
    if (selectedDistribuidoras.contains(d)) {
      selectedDistribuidoras.remove(d);
    } else {
      selectedDistribuidoras.add(d);
    }
    selectedDistribuidora = selectedDistribuidoras.isNotEmpty ? selectedDistribuidoras.first : null;
    notifyListeners();
  }

  // --- Dados importados ---
  List<Asset> assets = [];
  List<CandidateSite> candidateSites = [];
  // Guarda separado por distribuidora (preenchido no momento da busca, já
  // que candidate_site não necessariamente devolve o campo distribuidora
  // de volta) — é isso que permite rodar a otimização de cada uma
  // separadamente e colorir o Mapa por empresa, mesmo com tudo junto.
  Map<String, List<Asset>> assetsByDistribuidora = {};
  Map<String, List<CandidateSite>> candidateSitesByDistribuidora = {};
  bool loadingData = false;
  bool dataImported = false;

  // --- Parâmetros de cobertura de RF ---
  CoverageParams params = const CoverageParams();

  // --- Otimização ---
  bool running = false;
  ScenarioResult? currentResult;

  // IDs dos locais candidatos que viraram gateway por TOQUE MANUAL no mapa
  // (não pelo algoritmo). Usado só pra explicar corretamente "por que esse
  // gateway está aqui" — reseta toda vez que uma otimização de verdade roda.
  final Set<String> manualGatewayIds = {};

  // --- Comparação de cenários ---
  final List<ScenarioResult> scenarioHistory = [];
  bool _scenarioHistoryLoaded = false;
  bool loadingScenarioHistory = false;

  String? lastSyncError; // erro ao sincronizar cenários com o backend
  String? terrainError; // aviso quando o cálculo com relevo não pôde ser feito
  TerrainStatus? terrainStatus; // arquivos .hgt que o backend encontrou
  bool updatingManual = false; // recalculando após marcar/desmarcar gateway com relevo
  String? dataError; // erro ao carregar distribuidoras/dados

  Future<void> loadDistribuidoras() async {
    loadingDistribuidoras = true;
    dataError = null;
    notifyListeners();
    try {
      final fetched = await _repository.fetchDistribuidoras();
      // As 5 distribuidoras sempre aparecem (mesmo que o banco ainda não tenha todas); o que vier a mais do banco também entra.
      const fixas = ['CPFL Paulista', 'CPFL Piratininga', 'EDP São Paulo', 'Enel São Paulo', 'Neoenergia Elektro'];
      distribuidoras = [...fixas, for (final d in fetched) if (!fixas.contains(d)) d];
      // Não seleciona nenhuma sozinho — com seleção múltipla, quem escolhe é o usuário (checkboxes).
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
    refreshTerrainStatus(); // não espera: é só um aviso na tela de Parâmetros
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

  // --- Pontos altos sugeridos (gateways novos onde o relevo hoje bloqueia) ---
  List<PeakSuggestion> peakSuggestions = [];
  bool suggestingPeaks = false;
  String? peakMessage;

  Future<void> suggestPeaks() async {
    if (planningApi == null) return;
    suggestingPeaks = true;
    peakMessage = null;
    notifyListeners();
    try {
      peakSuggestions = await planningApi!.suggestPeaks(params: params, groups: _planningGroups());
      if (peakSuggestions.isEmpty) peakMessage = 'Não achei pontos altos que recuperem ativos sem sinal.';
    } catch (e) {
      peakSuggestions = [];
      peakMessage = 'Não consegui sugerir pontos altos ($e).';
    }
    suggestingPeaks = false;
    notifyListeners();
  }

  void clearPeakSuggestions() {
    peakSuggestions = [];
    peakMessage = null;
    notifyListeners();
  }

  /// Adota o ponto alto como local candidato da distribuidora e recalcula.
  Future<void> usePeak(PeakSuggestion s) async {
    await addManualCandidateSite(
      name: 'Pico ${s.elevationM.round()} m',
      type: 'Ponto alto',
      latitude: s.point.latitude,
      longitude: s.point.longitude,
      distribuidora: s.group,
    );
    peakSuggestions = peakSuggestions.where((e) => e.id != s.id).toList();
    notifyListeners();
    await runOptimization();
  }

  Future<void> refreshTerrainStatus() async {
    if (planningApi == null) return;
    try {
      terrainStatus = await planningApi!.terrainStatus();
    } catch (_) {
      terrainStatus = null;
    }
    notifyListeners();
  }

  /// Um grupo por distribuidora (cada uma só usa os próprios locais candidatos).
  /// Com [gatewayIds], o backend só avalia esses gateways em vez de otimizar.
  List<PlanningGroup> _planningGroups({Set<String>? gatewayIds}) {
    final names = assetsByDistribuidora.keys.toSet()..addAll(candidateSitesByDistribuidora.keys);
    if (names.isEmpty) {
      return [PlanningGroup(name: 'Todos', assets: assets, candidates: candidateSites, manualGatewayIds: gatewayIds?.toList())];
    }
    final groups = <PlanningGroup>[];
    for (final d in names) {
      final a = assetsByDistribuidora[d] ?? const <Asset>[];
      final c = candidateSitesByDistribuidora[d] ?? const <CandidateSite>[];
      if (a.isEmpty || c.isEmpty) continue;
      final candidateIds = {for (final x in c) x.id};
      groups.add(PlanningGroup(
        name: d,
        assets: a,
        candidates: c,
        manualGatewayIds: gatewayIds == null ? null : gatewayIds.where(candidateIds.contains).toList(),
      ));
    }
    return groups;
  }

  List<CandidateSite> _gatewaysFromIds(List<String> ids) {
    final byId = {for (final c in candidateSites) c.id: c};
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
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
    if (selectedDistribuidoras.isEmpty) return;
    loadingData = true;
    dataError = null;
    notifyListeners();

    try {
      final newAssets = <Asset>[];
      final newCandidates = <CandidateSite>[];
      final newAssetsBy = <String, List<Asset>>{};
      final newCandidatesBy = <String, List<CandidateSite>>{};

      for (final d in selectedDistribuidoras) {
        final a = await _repository.fetchAssets(d);
        final c = await _repository.fetchCandidateSites(d);
        newAssets.addAll(a);
        newCandidates.addAll(c);
        newAssetsBy[d] = a;
        newCandidatesBy[d] = c;
      }

      assets = newAssets;
      candidateSites = newCandidates;
      assetsByDistribuidora = newAssetsBy;
      candidateSitesByDistribuidora = newCandidatesBy;
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
    final dist = selectedDistribuidora ?? '';
    final draft = Asset(
      id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      latitude: latitude,
      longitude: longitude,
      distribuidora: dist,
    );
    final saved = await _repository.createAsset(draft);
    assets = [...assets, saved];
    // Também entra no agrupamento por distribuidora — sem isso, esse
    // ativo nunca seria considerado na otimização (que roda separada por
    // distribuidora usando esse mapa, não a lista plana).
    assetsByDistribuidora = {
      ...assetsByDistribuidora,
      dist: [...(assetsByDistribuidora[dist] ?? const <Asset>[]), saved],
    };
    notifyListeners();
  }

  Future<void> addManualCandidateSite({required String name, required String type, required double latitude, required double longitude, String? distribuidora}) async {
    final dist = distribuidora ?? selectedDistribuidora ?? '';
    final draft = CandidateSite(id: 'temp-${DateTime.now().microsecondsSinceEpoch}', name: name, type: type, latitude: latitude, longitude: longitude);
    final saved = await _repository.createCandidateSite(draft, dist);
    candidateSites = [...candidateSites, saved];
    // Mesmo motivo do addManualAsset — sem isso, esse local candidato
    // nunca apareceria como opção na otimização por distribuidora, e
    // também não ganharia a cor certa no mapa (que usa esse mapa pra
    // saber de qual distribuidora é cada quadrado).
    candidateSitesByDistribuidora = {
      ...candidateSitesByDistribuidora,
      dist: [...(candidateSitesByDistribuidora[dist] ?? const <CandidateSite>[]), saved],
    };
    notifyListeners();
  }

  // Marca/desmarca um local candidato como gateway direto no mapa, sem
  // depender do algoritmo. Só afeta [currentResult] — não vira um cenário
  // salvo no histórico/backend (isso só acontece via runOptimization).
  Future<void> toggleManualGateway(CandidateSite site) async {
    final existing = currentResult;
    final base = existing?.chosenGateways ?? const <CandidateSite>[];
    final chosen = base.any((g) => g.id == site.id);
    final newGateways = chosen ? base.where((g) => g.id != site.id).toList() : [...base, site];

    // Registra que ESSE gateway específico entrou/saiu por toque manual,
    // pra "por que ele está aqui" explicar certo depois (e não dizer que
    // foi o algoritmo que escolheu, quando na verdade foi você).
    if (chosen) {
      manualGatewayIds.remove(site.id);
    } else {
      manualGatewayIds.add(site.id);
    }

    // Resultado calculado COM relevo: recalcula no backend, para a cobertura
    // continuar respeitando o relevo depois do ajuste manual.
    final base0 = existing;
    if (base0 != null && base0.terrain != null && base0.params.useTerrain && planningApi != null) {
      updatingManual = true;
      terrainError = null;
      notifyListeners();
      try {
        final analysis = await planningApi!.run(
          params: base0.params,
          groups: _planningGroups(gatewayIds: newGateways.map((g) => g.id).toSet()),
        );
        currentResult = ScenarioResult(
          id: base0.id,
          label: base0.label,
          executedAt: base0.executedAt,
          params: base0.params,
          chosenGateways: _gatewaysFromIds(analysis.chosenGatewayIds),
          totalAssets: assets.length,
          coveredAssets: analysis.coveredAssets,
          processingTime: base0.processingTime,
          terrain: analysis,
        );
      } catch (e) {
        // desfaz a marcação: o backend não confirmou
        if (chosen) {
          manualGatewayIds.add(site.id);
        } else {
          manualGatewayIds.remove(site.id);
        }
        terrainError = 'Não consegui recalcular com relevo: $e';
      }
      updatingManual = false;
      notifyListeners();
      return;
    }

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

    final scenarioLabel = label ?? 'Cenário ${scenarioHistory.length + 1}';
    final allChosen = <CandidateSite>[];
    var totalCovered = 0;
    var totalProcessing = Duration.zero;
    TerrainAnalysis? analysis;
    var usedParams = params;
    terrainError = null;

    // 1) Com relevo: o backend lê os .hgt, calcula o sinal de cada enlace e escolhe os gateways.
    if (params.useTerrain && planningApi != null) {
      final sw = Stopwatch()..start();
      try {
        final a = await planningApi!.run(params: params, groups: _planningGroups());
        analysis = a;
        allChosen.addAll(_gatewaysFromIds(a.chosenGatewayIds));
        totalCovered = a.coveredAssets;
        totalProcessing = sw.elapsed;
        if (!a.terrainUsed) {
          // backend não achou os .hgt: o resultado é só por distância e a tela precisa dizer isso
          usedParams = params.copyWith(useTerrain: false);
          terrainError = a.warnings.isEmpty ? 'O backend não encontrou arquivos de relevo; o cálculo usou só a distância.' : a.warnings.join(' ');
        }
      } catch (e) {
        analysis = null;
        usedParams = params.copyWith(useTerrain: false);
        terrainError = 'Não consegui calcular com relevo ($e). Usei só a distância.';
      }
    } else if (params.useTerrain) {
      usedParams = params.copyWith(useTerrain: false);
    }

    // 2) Só distância (como antes): roda a otimização SEPARADA pra cada
    // distribuidora — cada uma só pode usar os próprios locais candidatos
    // como gateway. O resultado final junta os gateways de cada uma.
    if (analysis == null) {
      final distribuidorasComDado = assetsByDistribuidora.keys.toSet()..addAll(candidateSitesByDistribuidora.keys);

      if (distribuidorasComDado.isEmpty) {
        // Dado veio de outro jeito (ex.: só manual, sem passar por importData)
        // — nesse caso cai pro comportamento antigo, tudo junto num problema só.
        final r = _optimizationService.run(label: scenarioLabel, assets: assets, candidates: candidateSites, params: params);
        allChosen.addAll(r.chosenGateways);
        totalCovered = r.coveredAssets;
        totalProcessing = r.processingTime;
      } else {
        for (final d in distribuidorasComDado) {
          final distAssets = assetsByDistribuidora[d] ?? const <Asset>[];
          final distCandidates = candidateSitesByDistribuidora[d] ?? const <CandidateSite>[];
          if (distAssets.isEmpty || distCandidates.isEmpty) continue;
          final partial = _optimizationService.run(label: scenarioLabel, assets: distAssets, candidates: distCandidates, params: params);
          allChosen.addAll(partial.chosenGateways);
          totalCovered += partial.coveredAssets;
          totalProcessing += partial.processingTime;
        }
      }
    }

    var result = ScenarioResult(
      id: 'scenario-${DateTime.now().microsecondsSinceEpoch}',
      label: scenarioLabel,
      executedAt: DateTime.now(),
      params: usedParams,
      chosenGateways: allChosen,
      totalAssets: assets.length,
      coveredAssets: totalCovered,
      processingTime: totalProcessing,
      terrain: analysis,
    );

    if (scenarioApi != null && selectedDistribuidoras.isNotEmpty) {
      try {
        // o banco guarda o resumo; os detalhes do relevo (ligações, áreas) ficam só em memória
        result = (await scenarioApi!.createScenario(local: result, distribuidora: selectedDistribuidoras.join(' + '))).withTerrain(analysis);
        lastSyncError = null;
      } catch (e) {
        lastSyncError = e.toString();
      }
    }

    currentResult = result;
    scenarioHistory.add(result);
    manualGatewayIds.clear(); // gateways dessa rodada vieram todos do algoritmo
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