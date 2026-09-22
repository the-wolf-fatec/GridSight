/// Local candidato à instalação de um gateway (poste, subestação, etc.)
class CandidateSite {
  final String id;
  final String name;
  final String type; // ex: poste, subestacao
  final double latitude;
  final double longitude;

  const CandidateSite({
    required this.id,
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
  });
}
