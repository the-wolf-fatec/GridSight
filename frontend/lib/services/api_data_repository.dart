import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/asset.dart';
import '../models/candidate_site.dart';
import 'data_repository.dart';

/// Implementação de [DataRepository] que consome a API REST do backend
/// Spring Boot + MySQL via HTTP (ver `main.dart` pra trocar entre mock e
/// este repositório).
class ApiDataRepository implements DataRepository {
  ApiDataRepository({required this.baseUrl, this.timeout = const Duration(seconds: 15)});

  final String baseUrl;
  final Duration timeout;

  @override
  Future<List<String>> fetchDistribuidoras() async {
    final list = await _request('GET', '/distribuidoras') as List;
    return list.map((e) => e.toString()).toList();
  }

  @override
  Future<List<Asset>> fetchAssets(String distribuidora) async {
    final list = await _request('GET', '/assets', query: {'distribuidora': distribuidora}) as List;
    return list.map((j) => _assetFromJson(j)).toList();
  }

  @override
  Future<List<CandidateSite>> fetchCandidateSites(String distribuidora) async {
    final list = await _request('GET', '/candidate-sites', query: {'distribuidora': distribuidora}) as List;
    return list.map((j) => _candidateFromJson(j)).toList();
  }

  @override
  Future<Asset> createAsset(Asset asset) async {
    final json = await _request('POST', '/assets', body: {
      'id': asset.id,
      'name': asset.name,
      'type': asset.type,
      'latitude': asset.latitude,
      'longitude': asset.longitude,
      'distribuidora': asset.distribuidora,
    });
    return _assetFromJson(json);
  }

  @override
  Future<List<Asset>> fetchManualAssets() async {
    final list = await _request('GET', '/assets/manual') as List;
    return list.map((j) => _assetFromJson(j)).toList();
  }

  @override
  Future<CandidateSite> createCandidateSite(CandidateSite site, String distribuidora) async {
    final json = await _request('POST', '/candidate-sites', body: {
      'id': site.id,
      'name': site.name,
      'type': site.type,
      'latitude': site.latitude,
      'longitude': site.longitude,
      'distribuidora': distribuidora,
    });
    return _candidateFromJson(json);
  }

  @override
  Future<List<CandidateSite>> fetchManualCandidateSites() async {
    final list = await _request('GET', '/candidate-sites/manual') as List;
    return list.map((j) => _candidateFromJson(j)).toList();
  }

  // --- Parsing ---

  Asset _assetFromJson(Map<String, dynamic> j) => Asset(
        id: j['id'].toString(),
        name: j['name'] as String,
        type: j['type'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        distribuidora: j['distribuidora'] as String,
      );

  CandidateSite _candidateFromJson(Map<String, dynamic> j) => CandidateSite(
        id: j['id'].toString(),
        name: j['name'] as String,
        type: j['type'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
      );

  // --- HTTP ---

  Future<dynamic> _request(String method, String path, {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);

    http.Response response;
    try {
      response = method == 'POST'
          ? await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(timeout)
          : await http.get(uri).timeout(timeout);
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

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw ApiException('Resposta de $uri não é um JSON válido: $e');
    }
  }
}

/// Erro na comunicação com o backend (rede, HTTP, parsing).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
