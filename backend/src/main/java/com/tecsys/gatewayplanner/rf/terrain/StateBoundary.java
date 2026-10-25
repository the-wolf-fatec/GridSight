package com.tecsys.gatewayplanner.rf.terrain;

import java.awt.geom.Path2D;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * Contorno de um estado (anéis externos de polígonos, em lon/lat). Usado para recortar
 * a camada de relevo no formato do estado. Formato do arquivo: uma linha por anel,
 * "lon,lat lon,lat ...".
 */
public final class StateBoundary {

    private final List<double[]> rings = new ArrayList<>(); // cada anel: lon0,lat0,lon1,lat1,...

    private StateBoundary() {
    }

    /** Contorno de São Paulo, empacotado em {@code sp-boundary.txt}; nulo se o arquivo não existir. */
    public static StateBoundary loadSp() {
        try (InputStream in = StateBoundary.class.getResourceAsStream("/sp-boundary.txt")) {
            return in == null ? null : read(in);
        } catch (IOException | RuntimeException e) {
            return null;
        }
    }

    public static StateBoundary read(InputStream in) throws IOException {
        StateBoundary b = new StateBoundary();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty()) continue;
                String[] pts = line.split(" ");
                double[] ring = new double[pts.length * 2];
                for (int i = 0; i < pts.length; i++) {
                    String[] ll = pts[i].split(",");
                    ring[2 * i] = Double.parseDouble(ll[0]);
                    ring[2 * i + 1] = Double.parseDouble(ll[1]);
                }
                b.rings.add(ring);
            }
        }
        return b;
    }

    /** O ponto está dentro do estado? */
    public boolean contains(double lat, double lon) {
        for (double[] ring : rings) {
            boolean in = false;
            int n = ring.length / 2;
            for (int i = 0, j = n - 1; i < n; j = i++) {
                double xi = ring[2 * i], yi = ring[2 * i + 1], xj = ring[2 * j], yj = ring[2 * j + 1];
                if ((yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) in = !in;
            }
            if (in) return true;
        }
        return false;
    }

    /** O contorno em coordenadas de pixel de um tile (Web Mercator), para usar como recorte. */
    public Path2D tileShape(int z, int tx, int ty) {
        double n = 1 << z;
        Path2D.Double path = new Path2D.Double(Path2D.WIND_NON_ZERO);
        for (double[] ring : rings) {
            for (int i = 0; i < ring.length / 2; i++) {
                double lon = ring[2 * i], lat = Math.toRadians(ring[2 * i + 1]);
                double px = ((lon + 180.0) / 360.0 * n - tx) * 256.0;
                double py = ((1.0 - Math.log(Math.tan(lat) + 1.0 / Math.cos(lat)) / Math.PI) / 2.0 * n - ty) * 256.0;
                if (i == 0) path.moveTo(px, py);
                else path.lineTo(px, py);
            }
            path.closePath();
        }
        return path;
    }
}
