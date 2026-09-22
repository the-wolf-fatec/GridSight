/// Representa um ativo da rede elétrica (ponto a ser coberto),
/// tipicamente importado da BDGD (Base de Dados Geográfica da Distribuidora).
class Asset {
  final String id;
  final String name;
  final String type; // ex: sensor, medidor, chave, transformador
  final double latitude;
  final double longitude;
  final String distribuidora;

  const Asset({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distribuidora,
  });
}
