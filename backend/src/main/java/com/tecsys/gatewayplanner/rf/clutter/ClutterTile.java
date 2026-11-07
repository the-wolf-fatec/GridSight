package com.tecsys.gatewayplanner.rf.clutter;

import java.util.Arrays;

/**
 * Grade de obstáculos de um ladrilho de 0,05° (~5,5 km) com células de 0,0002° (~22 m).
 * Cada célula guarda 1 byte: bits 0..6 = maior altura (m, 0..127) do obstáculo que cobre a célula;
 * bit 7 = 1 se esse obstáculo é árvore/mata (0 = prédio).
 */
public final class ClutterTile {

    public static final double TILE_DEG = 0.05;
    public static final double CELL_DEG = 0.0002;
    public static final int N = (int) Math.round(TILE_DEG / CELL_DEG); // 250

    public final int tileI; // floor(lat / TILE_DEG)
    public final int tileJ; // floor(lon / TILE_DEG)
    private final byte[] h;

    public ClutterTile(int tileI, int tileJ) {
        this(tileI, tileJ, new byte[N * N]);
    }

    public ClutterTile(int tileI, int tileJ, byte[] data) {
        if (data.length != N * N) throw new IllegalArgumentException("Tamanho inválido do ladrilho de obstáculos.");
        this.tileI = tileI;
        this.tileJ = tileJ;
        this.h = data;
    }

    public static int tileIndex(double deg) {
        return (int) Math.floor(deg / TILE_DEG + 1e-9);
    }

    public static long key(int i, int j) {
        return ((long) i << 32) ^ (j & 0xffffffffL);
    }

    public long key() {
        return key(tileI, tileJ);
    }

    public byte[] data() {
        return h;
    }

    private double lat0() {
        return tileI * TILE_DEG;
    }

    private double lon0() {
        return tileJ * TILE_DEG;
    }

    private int raw(double lat, double lon) {
        int r = (int) Math.floor((lat - lat0()) / CELL_DEG);
        int c = (int) Math.floor((lon - lon0()) / CELL_DEG);
        if (r < 0 || c < 0 || r >= N || c >= N) return 0;
        return h[r * N + c] & 0xff;
    }

    /** Altura (m) do obstáculo no ponto, 0 = livre. */
    public double heightAt(double lat, double lon) {
        return raw(lat, lon) & 0x7f;
    }

    /** 0 = livre, 1 = árvore/mata, 2 = prédio. */
    public int kindAt(double lat, double lon) {
        int v = raw(lat, lon);
        if ((v & 0x7f) == 0) return 0;
        return (v & 0x80) != 0 ? 1 : 2;
    }

    private void raise(int r, int c, int height, boolean tree) {
        if (r < 0 || c < 0 || r >= N || c >= N) return;
        int i = r * N + c;
        height = Math.min(127, height);
        if ((h[i] & 0x7f) < height) h[i] = (byte) (height | (tree ? 0x80 : 0));
    }

    /** Preenche um retângulo (caixa envolvente de um prédio). */
    public void fillRect(double minLat, double minLon, double maxLat, double maxLon, int height, boolean tree) {
        int r0 = (int) Math.floor((minLat - lat0()) / CELL_DEG);
        int r1 = (int) Math.floor((maxLat - lat0()) / CELL_DEG);
        int c0 = (int) Math.floor((minLon - lon0()) / CELL_DEG);
        int c1 = (int) Math.floor((maxLon - lon0()) / CELL_DEG);
        for (int r = Math.max(0, r0); r <= Math.min(N - 1, r1); r++) {
            for (int c = Math.max(0, c0); c <= Math.min(N - 1, c1); c++) raise(r, c, height, tree);
        }
    }

    /** Preenche um polígono (regra par-ímpar) pelas linhas de varredura. */
    public void fillPolygon(double[] lats, double[] lons, int height, boolean tree) {
        int n = lats.length;
        if (n < 3) return;
        double minLat = Double.MAX_VALUE, maxLat = -Double.MAX_VALUE;
        for (double v : lats) {
            minLat = Math.min(minLat, v);
            maxLat = Math.max(maxLat, v);
        }
        int r0 = Math.max(0, (int) Math.floor((minLat - lat0()) / CELL_DEG));
        int r1 = Math.min(N - 1, (int) Math.floor((maxLat - lat0()) / CELL_DEG));
        double[] xs = new double[n];
        for (int r = r0; r <= r1; r++) {
            double y = lat0() + (r + 0.5) * CELL_DEG;
            int k = 0;
            for (int a = 0, b = n - 1; a < n; b = a++) {
                double ya = lats[a], yb = lats[b];
                if ((ya > y) != (yb > y)) {
                    xs[k++] = lons[a] + (y - ya) / (yb - ya) * (lons[b] - lons[a]);
                }
            }
            Arrays.sort(xs, 0, k);
            for (int m = 0; m + 1 < k; m += 2) {
                int c0 = (int) Math.ceil((xs[m] - lon0()) / CELL_DEG - 0.5);
                int c1 = (int) Math.floor((xs[m + 1] - lon0()) / CELL_DEG - 0.5);
                for (int c = Math.max(0, c0); c <= Math.min(N - 1, c1); c++) raise(r, c, height, tree);
            }
        }
    }
}
