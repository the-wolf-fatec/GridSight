import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/asset.dart';
import '../models/candidate_site.dart';
import '../models/coverage_params.dart';
import '../models/elevation_profile.dart';
import '../models/terrain_analysis.dart';
import 'api_data_repository.dart' show ApiException;

/// Planejamento com relevo: manda ativos e candidatos para o backend, que
/// calcula o sinal de cada enlace usando os arquivos .hgt (SRTM) e devolve
/// os gateways escolhidos, quem atende quem e a influência do relevo.
class PlanningApiService {
  PlanningApiService({required this.baseUrl, this.timeout = const Duration(minutes: 10)});

  final String baseUrl;
  final Duration timeout;

  /// [groups] = um por distribuidora. Se [manualGatewayIds] vier em um grupo,
  /// o backend só AVALIA esses gateways (não otimiza).
  Map<String, dynamic> _body(CoverageParams params, List<PlanningGroup> groups) => {
        'rangeKm': params.effectiveRangeKm,
        'gatewayHeightM': params.gatewayHeightM,
        'fadeMarginDb': params.fadeMarginDb,
        'txPowerDbm': params.transmissionPowerDbm,
        'minCoverageTarget': params.minCoverageTarget,
        'maxGateways': params.maxGateways,
        'useTerrain': true,
        'useClutter': params.useClutter,
        'groups': [for (final g in groups) g.toJson()],
      };

  /// Pontos altos onde um gateway novo recuperaria ativos sem sinal por causa do relevo.
  Future<List<PeakSuggestion>> suggestPeaks({required CoverageParams params, required List<PlanningGroup> groups}) async {
    final json = await _request('POST', '/planning/suggest-peaks', body: _body(params, groups));
    return [for (final e in (json as List)) PeakSuggestion.fromJson(e as Map<String, dynamic>)];
  }

  Future<TerrainAnalysis> run({
    required CoverageParams params,
    required List<PlanningGroup> groups,
    Duration? timeout,
  }) async {
    final body = {
      'rangeKm': params.effectiveRangeKm,
      'gatewayHeightM': params.gatewayHeightM,
        'fadeMarginDb': params.fadeMarginDb,
      'txPowerDbm': params.transmissionPowerDbm,
      'minCoverageTarget': params.minCoverageTarget,
      'maxGateways': params.maxGateways,
      'useTerrain': params.useTerrain,
      'useClutter': params.useClutter,
      'groups': [for (final g in groups) g.toJson()],
    };
    final json = await _request('POST', '/planning/run', body: body, timeout: timeout);
    return TerrainAnalysis.fromJson(json as Map<String, dynamic>);
  }

  /// Perfil de elevação entre dois pontos (gateway e ativo): chão, linha de visada e Fresnel.
  Future<ElevationProfile> elevationProfile({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
    double gatewayHeightM = 6,
    double deviceHeightM = 5,
  }) async {
    final q = 'lat1=$lat1&lon1=$lon1&lat2=$lat2&lon2=$lon2&h1=$gatewayHeightM&h2=$deviceHeightM&n=140';
    final json = await _request('GET', '/planning/profile?$q');
    return ElevationProfile.fromJson(json as Map<String, dynamic>);
  }

  /// Registra no backend a região escolhida (pontos da rede das distribuidoras selecionadas);
  /// devolve um id que vai na URL dos tiles de relevo para pintá-lo SÓ nessa região.
  Future<String> registerRegion(List<List<double>> points, {double radiusKm = 8}) async {
    final json = await _request('POST', '/terrain/regions', body: {'points': points, 'radiusKm': radiusKm});
    return (json as Map<String, dynamic>)['id'].toString();
  }

  Future<TerrainStatus> terrainStatus() async {
    final json = await _request('GET', '/planning/terrain-status');
    return TerrainStatus.fromJson(json as Map<String, dynamic>);
  }

  Future<dynamic> _request(String method, String path, {Object? body, Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    http.Response response;
    try {
      response = method == 'POST'
          ? await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(timeout ?? this.timeout)
          : await http.get(uri).timeout(const Duration(seconds: 8));
    } catch (e) {
      throw ApiException('Não foi possível falar com o backend em $baseUrl ($e). Ele está rodando?');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Backend retornou ${response.statusCode} em $path: ${utf8.decode(response.bodyBytes)}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw ApiException('Resposta de $path não é um JSON válido: $e');
    }
  }
}

/// Ativos e candidatos de UMA distribuidora (cada uma só usa os próprios locais).
class PlanningGroup {
  final String name;
  final List<Asset> assets;
  final List<CandidateSite> candidates;
  final List<String>? manualGatewayIds;

  const PlanningGroup({required this.name, required this.assets, required this.candidates, this.manualGatewayIds});

  Map<String, dynamic> toJson() => {
        'name': name,
        'assets': [
          for (final a in assets) {'id': a.id, 'name': a.name, 'type': a.type, 'lat': a.latitude, 'lon': a.longitude},
        ],
        'candidates': [
          for (final c in candidates) {'id': c.id, 'name': c.name, 'type': c.type, 'lat': c.latitude, 'lon': c.longitude},
        ],
        if (manualGatewayIds != null) 'manualGatewayIds': manualGatewayIds,
      };
}
