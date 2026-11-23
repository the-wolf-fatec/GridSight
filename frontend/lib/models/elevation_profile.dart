/// Um ponto do perfil de elevação (alturas em metros acima do nível do mar).
class ProfileSample {
  final double distanceKm;
  final double groundM; // chão já com a curvatura da Terra
  final double lineOfSightM; // linha reta entre as duas antenas
  final double fresnelLowerM; // limite inferior de 60% da 1ª zona de Fresnel

  const ProfileSample({required this.distanceKm, required this.groundM, required this.lineOfSightM, required this.fresnelLowerM});

  factory ProfileSample.fromJson(Map<String, dynamic> j) => ProfileSample(
        distanceKm: (j['distanceKm'] as num).toDouble(),
        groundM: (j['groundM'] as num).toDouble(),
        lineOfSightM: (j['lineOfSightM'] as num).toDouble(),
        fresnelLowerM: (j['fresnelLowerM'] as num).toDouble(),
      );
}

/// Resposta de GET /api/planning/profile.
class ElevationProfile {
  final List<ProfileSample> samples;
  final double distanceKm;
  final double minClearanceM; // negativo = o terreno corta a visada
  final double worstDistanceKm;
  final bool blocked;
  final bool fresnelObstructed;
  final int dataMissing;
  final bool hasData;

  const ElevationProfile({
    required this.samples,
    required this.distanceKm,
    required this.minClearanceM,
    required this.worstDistanceKm,
    required this.blocked,
    required this.fresnelObstructed,
    required this.dataMissing,
    required this.hasData,
  });

  factory ElevationProfile.fromJson(Map<String, dynamic> j) => ElevationProfile(
        samples: [for (final s in ((j['samples'] as List?) ?? const [])) ProfileSample.fromJson(s as Map<String, dynamic>)],
        distanceKm: (j['distanceKm'] as num).toDouble(),
        minClearanceM: (j['minClearanceM'] as num).toDouble(),
        worstDistanceKm: (j['worstDistanceKm'] as num).toDouble(),
        blocked: j['blocked'] as bool,
        fresnelObstructed: j['fresnelObstructed'] as bool,
        dataMissing: (j['dataMissing'] as num).toInt(),
        hasData: j['hasData'] as bool,
      );
}
