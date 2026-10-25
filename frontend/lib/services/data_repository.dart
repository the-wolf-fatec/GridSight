import '../models/asset.dart';
import '../models/candidate_site.dart';

/// Contrato de acesso a dados usado pelo app. Implementado por
/// [MockDataRepository] (memória) e [ApiDataRepository] (Spring Boot).
abstract class DataRepository {
  Future<List<String>> fetchDistribuidoras();
  Future<List<Asset>> fetchAssets(String distribuidora);
  Future<List<CandidateSite>> fetchCandidateSites(String distribuidora);

  Future<Asset> createAsset(Asset asset);
  Future<List<Asset>> fetchManualAssets(); // só os criados manualmente

  // CandidateSite não carrega `distribuidora` (a API nunca devolve isso em
  // leitura), então precisa vir à parte aqui na criação.
  Future<CandidateSite> createCandidateSite(CandidateSite site, String distribuidora);
  Future<List<CandidateSite>> fetchManualCandidateSites();
}
