package com.tecsys.gatewayplanner.rf.terrain;

import java.awt.geom.Ellipse2D;
import java.awt.geom.Path2D;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Região escolhida pelo usuário (as distribuidoras selecionadas): a união de círculos em volta
 * dos pontos da rede. Serve para pintar o relevo SÓ onde há rede, em qualquer lugar do Brasil.
 * Não depende do Spring.
 */
public final class RegionMask implements TileClip {

    private static final double GRID_DEG = 0.02; // ~2 km: pontos mais próximos que isso viram um só

    private final double[][] points; // {lat, lon}
    private final double radiusKm;

    private RegionMask(double[][] points, double radiusKm) {
        this.points = points;
        this.radiusKm = radiusKm;
    }

    /**
     * @param latLon   pontos {lat, lon} da rede (ativos e candidatos)
     * @param radiusKm quanto o relevo "sobra" em volta de cada ponto (limitado a 1..60 km)
     */
    public static RegionMask of(List<double[]> latLon, double radiusKm) {
        Set<Long> seen = new HashSet<>();
        List<double[]> keep = new ArrayList<>();
        for (double[] p : latLon) {
            if (p == null || p.length < 2 || Double.isNaN(p[0]) || Double.isNaN(p[1])) continue;
            if (Math.abs(p[0]) > 85 || Math.abs(p[1]) > 180) continue;
            long key = (((long) Math.floor(p[0] / GRID_DEG)) << 32) ^ (((long) Math.floor(p[1] / GRID_DEG)) & 0xFFFFFFFFL);
            if (seen.add(key)) keep.add(new double[]{p[0], p[1]});
            if (keep.size() >= 50_000) break;
        }
        double r = Math.max(1, Math.min(60, radiusKm));
        return new RegionMask(keep.toArray(new double[0][]), r);
    }

    public int size() {
        return points.length;
    }

    /** Identificador estável: a mesma seleção sempre gera o mesmo id (o cache de tiles continua valendo). */
    public String id() {
        long h = 1125899906842597L;
        for (double[] p : points) {
            h = 31 * h + Math.round(p[0] / GRID_DEG);
            h = 31 * h + Math.round(p[1] / GRID_DEG);
        }
        h = 31 * h + Math.round(radiusKm * 10);
        return Long.toHexString(h);
    }

    @Override
    public Path2D tileShape(int z, int tx, int ty) {
        double n = 1 << z;
        Path2D.Double path = new Path2D.Double(Path2D.WIND_NON_ZERO);
        for (double[] p : points) {
            double lat = p[0], lon = p[1];
            double metersPerPx = 156543.03392 * Math.cos(Math.toRadians(lat)) / Math.pow(2, z);
            double rPx = radiusKm * 1000.0 / metersPerPx;
            double px = ((lon + 180.0) / 360.0 * n - tx) * 256.0;
            double latRad = Math.toRadians(lat);
            double py = ((1.0 - Math.log(Math.tan(latRad) + 1.0 / Math.cos(latRad)) / Math.PI) / 2.0 * n - ty) * 256.0;
            if (px + rPx < 0 || px - rPx > 256 || py + rPx < 0 || py - rPx > 256) continue; // fora do tile
            path.append(new Ellipse2D.Double(px - rPx, py - rPx, 2 * rPx, 2 * rPx), false);
        }
        return path;
    }
}
