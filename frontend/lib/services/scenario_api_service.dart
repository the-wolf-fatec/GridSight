import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/candidate_site.dart';
import '../models/coverage_params.dart';
import '../models/scenario_result.dart';
import 'api_data_repository.dart' show ApiException;

/// Consome os endpoints de cenário (`/api/scenarios`) do backend, mantendo
/// o histórico de "Comparar Cenários" persistido no MySQL. Opcional —
/// [AppState] funciona sem isso, mantendo o histórico só em memória.
class ScenarioApiService {
  ScenarioApiService({required this.baseUrl, this.timeout = const Duration(seconds: 8)});

  final String baseUrl;
  final Duration timeout;

  Future<List<ScenarioResult>> fetchScenarios() async {
    final list = await _request('GET', '/scenarios') as List;
    return list.map((j) => _scenarioFromJson(j)).toList();
  }

  Future<ScenarioResult> createScenario({required ScenarioResult local, required String distribuidora}) async {
    final json = await _request('POST', '/scenarios', body: {
      'label': local.label,
      'distribuidora': distribuidora,
      'rangeKm': local.params.rangeKm,
      'transmissionPower': local.params.transmissionPowerDbm,
      'minCoverageTarget': local.params.minCoverageTarget,
      'maxGateways': local.params.maxGateways,
      'totalAssets': local.totalAssets,
      'coveredAssets': local.coveredAssets,
      'processingTimeMs': local.processingTime.inMilliseconds,
      'chosenGatewayIds': local.chosenGateways.map((g) => g.id).toList(),
    });
    return _scenarioFromJson(json);
  }

  Future<void> deleteScenario(String id) => _request('DELETE', '/scenarios/$id');

  Future<void> deleteAllScenarios() => _request('DELETE', '/scenarios');

  // --- Parsing ---

  ScenarioResult _scenarioFromJson(Map<String, dynamic> j) => ScenarioResult(
        id: j['id'] as String,
        label: j['label'] as String,
        executedAt: DateTime.parse(j['executedAt'] as String),
        params: CoverageParams(
          rangeKm: (j['rangeKm'] as num).toDouble(),
          transmissionPowerDbm: (j['transmissionPower'] as num).toDouble(),
          minCoverageTarget: (j['minCoverageTarget'] as num).toDouble(),
          maxGateways: j['maxGateways'] as int,
        ),
        chosenGateways: (j['chosenGateways'] as List).map((g) => _candidateFromJson(g)).toList(),
        totalAssets: j['totalAssets'] as int,
        coveredAssets: j['coveredAssets'] as int,
        processingTime: Duration(milliseconds: j['processingTimeMs'] as int),
      );

  CandidateSite _candidateFromJson(Map<String, dynamic> j) => CandidateSite(
        id: j['id'].toString(),
        name: j['name'] as String,
        type: j['type'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
      );

  // --- HTTP ---

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response response;

    try {
      response = switch (method) {
        'POST' => await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(timeout),
        'DELETE' => await http.delete(uri).timeout(timeout),
        _ => await http.get(uri).timeout(timeout),
      };
    } on SocketException catch (e) {
      throw ApiException('Não foi possível conectar ao backend em $baseUrl. Ele está rodando? Detalhe: $e');
    } on HttpException {
      throw ApiException('Erro de HTTP ao acessar $uri.');
    } on FormatException {
      throw ApiException('URL inválida: $uri.');
    } catch (e) {
      throw ApiException('Falha ao chamar $uri: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Backend retornou ${response.statusCode} para $uri: ${response.body}');
    }
    if (response.bodyBytes.isEmpty) return null;

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw ApiException('Resposta de $uri não é um JSON válido: $e');
    }
  }
}
