package com.tecsys.gatewayplanner.rf;

/** Utilitários geográficos. */
public final class Geo {
    public static final double EARTH_RADIUS_KM = 6371.0088;

    private Geo() {
    }

    /** Distância de grande círculo (haversine), em km. */
    public static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
        double p1 = Math.toRadians(lat1), p2 = Math.toRadians(lat2);
        double dp = p2 - p1, dl = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dp / 2) * Math.sin(dp / 2)
                + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1.0, Math.sqrt(a)));
    }
}
