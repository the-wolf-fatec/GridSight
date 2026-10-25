import 'package:latlong2/latlong.dart';

/// Um ativo atendido por um gateway (o de melhor sinal).
class AssetLink {
  final String assetId;
  final String gatewayId;
  final double distanceKm;
  final double rxDbm; // potência recebida estimada

  const AssetLink({required this.assetId, required this.gatewayId, required this.distanceKm, required this.rxDbm});

  factory AssetLink.fromJson(Map<String, dynamic> j) => AssetLink(
        assetId: j['assetId'].toString(),
        gatewayId: j['gatewayId'].toString(),
        distanceKm: (j['distanceKm'] as num).toDouble(),
        rxDbm: (j['rxDbm'] as num).toDouble(),
      );
}

/// Ponto do relevo que impede o sinal: altitude (m acima do nível do mar) e quanto passa da linha de visada.
class TerrainObstacle {
  final LatLng point;
  final double elevationM;
  final double aboveLineOfSightM;
  final double distanceKm; // do gateway

  const TerrainObstacle({required this.point, required this.elevationM, required this.aboveLineOfSightM, required this.distanceKm});

  factory TerrainObstacle.fromJson(Map<String, dynamic> j) => TerrainObstacle(
        point: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        elevationM: (j['elevationM'] as num).toDouble(),
        aboveLineOfSightM: (j['aboveLineOfSightM'] as num).toDouble(),
        distanceKm: (j['distanceKm'] as num).toDouble(),
      );
}

/// Ativo sem sinal por causa do relevo: altitude do local e o morro que o isola do gateway.
class LostAssetInfo {
  final String assetId;
  final double elevationM; // altitude do local (-9999 = sem dado)
  final String? gatewayId;
  final TerrainObstacle? blocker;

  const LostAssetInfo({required this.assetId, required this.elevationM, this.gatewayId, this.blocker});

  bool get hasElevation => elevationM > -9000;

  factory LostAssetInfo.fromJson(Map<String, dynamic> j) => LostAssetInfo(
        assetId: j['assetId'].toString(),
        elevationM: (j['elevationM'] as num).toDouble(),
        gatewayId: j['gatewayId']?.toString(),
        blocker: j['blocker'] == null ? null : TerrainObstacle.fromJson(j['blocker'] as Map<String, dynamic>),
      );
}

/// Ponto alto sugerido para um gateway novo.
class PeakSuggestion {
  final String id;
  final String group; // distribuidora
  final LatLng point;
  final double elevationM;
  final int newlyCovered; // ativos hoje sem sinal que ele recuperaria

  const PeakSuggestion({required this.id, required this.group, required this.point, required this.elevationM, required this.newlyCovered});

  factory PeakSuggestion.fromJson(Map<String, dynamic> j) => PeakSuggestion(
        id: j['id'].toString(),
        group: (j['group'] ?? '').toString(),
        point: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        elevationM: (j['elevationM'] as num).toDouble(),
        newlyCovered: (j['newlyCovered'] as num).toInt(),
      );
}

/// "E se o relevo fosse ignorado?": quantos gateways o planejamento só por
/// distância escolheria e o que acontece com ELES quando o relevo entra na conta.
class TerrainComparison {
  final int gateways;
  final int coveredByDistance;
  final int coveredWithTerrain;

  const TerrainComparison({required this.gateways, required this.coveredByDistance, required this.coveredWithTerrain});

  factory TerrainComparison.fromJson(Map<String, dynamic> j) => TerrainComparison(
        gateways: j['gateways'] as int,
        coveredByDistance: j['coveredByDistance'] as int,
        coveredWithTerrain: j['coveredWithTerrain'] as int,
      );
}

/// Resposta do planejamento com relevo (POST /api/planning/run).
class TerrainAnalysis {
  final bool terrainUsed; // false = o backend caiu para só distância (ex.: sem arquivos .hgt)
  final List<String> chosenGatewayIds;
  final Map<String, AssetLink> linkByAsset; // assetId -> gateway que o atende
  final Set<String> lostToTerrainIds; // ao alcance em linha reta, mas sem sinal por causa do relevo
  final int coveredIgnoringTerrain; // quantos esses mesmos gateways cobririam só por distância
  final int overlappedAssets; // ativos alcançados por 2+ gateways
  final TerrainComparison? withoutTerrain;
  final Map<String, List<LatLng>> footprints; // gatewayId -> contorno da área de cobertura
  final Map<String, LostAssetInfo> lostInfo; // assetId -> altitude e morro que bloqueia
  final Map<String, List<List<LatLng>>> shadows; // gatewayId -> buracos do alcance (sem sinal por causa do relevo)
  final Map<String, List<TerrainObstacle>> obstacles; // gatewayId -> morros que bloqueiam o sinal (do mais alto ao mais baixo)
  final List<String> warnings;
  final int totalAssets;
  final int coveredAssets;
  final int elapsedMs;

  const TerrainAnalysis({
    required this.terrainUsed,
    required this.chosenGatewayIds,
    required this.linkByAsset,
    required this.lostToTerrainIds,
    required this.coveredIgnoringTerrain,
    required this.overlappedAssets,
    required this.withoutTerrain,
    required this.footprints,
    this.obstacles = const {},
    this.shadows = const {},
    this.lostInfo = const {},
    required this.warnings,
    required this.totalAssets,
    required this.coveredAssets,
    required this.elapsedMs,
  });

  bool isCovered(String assetId) => linkByAsset.containsKey(assetId);

  /// Ativos atendidos por um gateway, do sinal mais forte ao mais fraco.
  List<AssetLink> linksOf(String gatewayId) {
    final out = linkByAsset.values.where((l) => l.gatewayId == gatewayId).toList();
    out.sort((a, b) => b.rxDbm.compareTo(a.rxDbm));
    return out;
  }

  factory TerrainAnalysis.fromJson(Map<String, dynamic> j) {
    final links = (j['links'] as List).map((e) => AssetLink.fromJson(e as Map<String, dynamic>));
    final fp = <String, List<LatLng>>{};
    final obs = <String, List<TerrainObstacle>>{};
    final sh = <String, List<List<LatLng>>>{};
    for (final f in (j['footprints'] as List)) {
      final m = f as Map<String, dynamic>;
      fp[m['gatewayId'].toString()] = [
        for (final p in (m['points'] as List)) LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ];
      sh[m['gatewayId'].toString()] = [
        for (final poly in ((m['shadows'] as List?) ?? const []))
          [for (final q in (poly as List)) LatLng((q[0] as num).toDouble(), (q[1] as num).toDouble())],
      ];
      obs[m['gatewayId'].toString()] = [
        for (final o in ((m['obstacles'] as List?) ?? const [])) TerrainObstacle.fromJson(o as Map<String, dynamic>),
      ];
    }
    return TerrainAnalysis(
      terrainUsed: j['terrainUsed'] as bool,
      chosenGatewayIds: (j['chosenGatewayIds'] as List).map((e) => e.toString()).toList(),
      linkByAsset: {for (final l in links) l.assetId: l},
      lostToTerrainIds: (j['lostToTerrainAssetIds'] as List).map((e) => e.toString()).toSet(),
      coveredIgnoringTerrain: j['coveredIgnoringTerrain'] as int,
      overlappedAssets: j['overlappedAssets'] as int,
      withoutTerrain: j['withoutTerrain'] == null ? null : TerrainComparison.fromJson(j['withoutTerrain'] as Map<String, dynamic>),
      footprints: fp,
      obstacles: obs,
      shadows: sh,
      lostInfo: {
        for (final e in ((j['lostDetails'] as List?) ?? const [])) (e['assetId'].toString()): LostAssetInfo.fromJson(e as Map<String, dynamic>),
      },
      warnings: (j['warnings'] as List).map((e) => e.toString()).toList(),
      totalAssets: j['totalAssets'] as int,
      coveredAssets: j['coveredAssets'] as int,
      elapsedMs: (j['elapsedMs'] as num).toInt(),
    );
  }
}

/// Situação dos arquivos de relevo no backend (GET /api/planning/terrain-status).
class TerrainStatus {
  final bool ok;
  final int tileCount;
  final String directory;
  final String hint; // o que fazer quando não achou arquivos

  const TerrainStatus({required this.ok, required this.tileCount, required this.directory, this.hint = ''});

  factory TerrainStatus.fromJson(Map<String, dynamic> j) => TerrainStatus(
        ok: j['ok'] as bool,
        tileCount: j['tileCount'] as int,
        directory: j['directory'].toString(),
        hint: (j['hint'] ?? '').toString(),
      );
}
