import 'dart:math';

import '../models/asset.dart';
import '../models/candidate_site.dart';
import 'data_repository.dart';

/// Implementação simulada do [DataRepository], usada enquanto o backend
/// em Spring Boot + MySQL ainda não está pronto (US1, US3, US9).
///
/// Gera dados geograficamente plausíveis ao redor de centros de referência,
/// imitando o formato de exportações da BDGD (ativos) e de locais físicos
/// candidatos (postes/subestações).
class MockDataRepository implements DataRepository {
  static final Map<String, _RegionSeed> _regions = {
    'EDP São Paulo': _RegionSeed(centerLat: -23.1791, centerLon: -45.8872, assetCount: 42, candidateCount: 16),
    'CPFL Paulista': _RegionSeed(centerLat: -22.9068, centerLon: -47.0626, assetCount: 36, candidateCount: 14),
    'Enel Rio': _RegionSeed(centerLat: -22.9068, centerLon: -43.1729, assetCount: 30, candidateCount: 12),
  };

  @override
  Future<List<String>> fetchDistribuidoras() async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _regions.keys.toList();
  }

  @override
  Future<List<Asset>> fetchAssets(String distribuidora) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final seed = _regions[distribuidora] ?? _regions.values.first;
    final rnd = Random(distribuidora.hashCode);
    const types = ['Sensor de Corrente', 'Medidor Inteligente', 'Chave Telecomandada', 'Religador'];

    return List.generate(seed.assetCount, (i) {
      final lat = seed.centerLat + (rnd.nextDouble() - 0.5) * 0.18;
      final lon = seed.centerLon + (rnd.nextDouble() - 0.5) * 0.18;
      return Asset(
        id: 'AT-${distribuidora.hashCode.toUnsigned(16)}-$i',
        name: '${types[i % types.length]} #${i + 1}',
        type: types[i % types.length],
        latitude: lat,
        longitude: lon,
        distribuidora: distribuidora,
      );
    });
  }

  @override
  Future<List<CandidateSite>> fetchCandidateSites(String distribuidora) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final seed = _regions[distribuidora] ?? _regions.values.first;
    final rnd = Random(distribuidora.hashCode ^ 0x5A5A);

    return List.generate(seed.candidateCount, (i) {
      final lat = seed.centerLat + (rnd.nextDouble() - 0.5) * 0.2;
      final lon = seed.centerLon + (rnd.nextDouble() - 0.5) * 0.2;
      final isSubestacao = i % 5 == 0;
      return CandidateSite(
        id: 'CS-${distribuidora.hashCode.toUnsigned(16)}-$i',
        name: isSubestacao ? 'Subestação ${i + 1}' : 'Poste ${i + 1}',
        type: isSubestacao ? 'subestacao' : 'poste',
        latitude: lat,
        longitude: lon,
      );
    });
  }

  @override
  Future<Asset> createAsset(Asset asset) async {
    // Sem backend real: só simula uma latência de rede e devolve o mesmo
    // ativo, como se tivesse sido salvo.
    await Future.delayed(const Duration(milliseconds: 300));
    return asset;
  }

  @override
  Future<List<Asset>> fetchManualAssets() async {
    // Modo mock não tem persistência real entre reloads da página (é tudo
    // memória do próprio processo Dart, que reinicia no F5) — então não há
    // nada pra restaurar aqui. Isso só funciona de verdade com o backend.
    await Future.delayed(const Duration(milliseconds: 150));
    return [];
  }

  @override
  Future<CandidateSite> createCandidateSite(CandidateSite site, String distribuidora) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return site;
  }

  @override
  Future<List<CandidateSite>> fetchManualCandidateSites() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return [];
  }
}

class _RegionSeed {
  final double centerLat;
  final double centerLon;
  final int assetCount;
  final int candidateCount;

  const _RegionSeed({
    required this.centerLat,
    required this.centerLon,
    required this.assetCount,
    required this.candidateCount,
  });
}
