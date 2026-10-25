package com.tecsys.gatewayplanner.rf.terrain;

import javax.imageio.ImageIO;
import java.awt.Graphics2D;
import java.awt.geom.Path2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

/**
 * Desenha os tiles de RELEVO (sombreado + cor por altitude) a partir dos mesmos dados
 * usados no cálculo de cobertura, recortados pelo contorno do estado: fora dele o tile
 * fica transparente (sem os "quadradinhos" de 1 grau dos arquivos .hgt).
 * Não depende do Spring.
 */
public final class TerrainTileRenderer {

    private static final int SIZE = 256;
    private static final int MIN_ZOOM = 6;

    private TerrainTileRenderer() {
    }

    /** PNG 256x256 com transparência. {@code boundary} nulo = não recorta. */
    public static byte[] png(TerrainProvider terrain, StateBoundary boundary, int z, int x, int y) throws IOException {
        BufferedImage out = new BufferedImage(SIZE, SIZE, BufferedImage.TYPE_INT_ARGB);
        int n = 1 << Math.max(0, Math.min(z, 22));
        if (z >= MIN_ZOOM && x >= 0 && y >= 0 && x < n && y < n) {
            Path2D clip = boundary == null ? null : boundary.tileShape(z, x, y);
            if (clip == null || clip.intersects(0, 0, SIZE, SIZE)) { // tile fora do estado: nem calcula
                BufferedImage img = new BufferedImage(SIZE, SIZE, BufferedImage.TYPE_INT_ARGB);
                render(terrain, img, z, x, y, n);
                if (clip == null) {
                    out = img;
                } else {
                    Graphics2D g = out.createGraphics();
                    g.setClip(clip);
                    g.drawImage(img, 0, 0, null);
                    g.dispose();
                }
            }
        }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ImageIO.write(out, "png", bytes);
        return bytes.toByteArray();
    }

    private static void render(TerrainProvider terrain, BufferedImage img, int z, int tx, int ty, int n) {
        // grade de elevação com 1 pixel de borda, para calcular a inclinação
        int g = SIZE + 2;
        double[][] elev = new double[g][g];
        for (int j = 0; j < g; j++) {
            double lat = pixelLat(ty, j - 1, n);
            for (int i = 0; i < g; i++) {
                double lon = pixelLon(tx, i - 1, n);
                elev[j][i] = terrain.elevationM(lat, lon);
            }
        }
        double midLat = pixelLat(ty, SIZE / 2, n);
        double pixM = 156543.03392 * Math.cos(Math.toRadians(midLat)) / Math.pow(2, z);
        // Em zoom aberto o relevo parece "achatado"; exagera a inclinação para o morro aparecer.
        double exaggeration = z <= 7 ? 6 : (z <= 9 ? 3 : 1.5);

        // luz vinda de noroeste, 45° de altura
        double az = Math.toRadians(315), alt = Math.toRadians(45);
        double lx = Math.sin(az) * Math.cos(alt), ly = Math.cos(az) * Math.cos(alt), lz = Math.sin(alt);

        for (int j = 1; j <= SIZE; j++) {
            for (int i = 1; i <= SIZE; i++) {
                double e = elev[j][i];
                if (Double.isNaN(e)) continue;
                double l = elev[j][i - 1], r = elev[j][i + 1], u = elev[j - 1][i], d = elev[j + 1][i];
                if (Double.isNaN(l) || Double.isNaN(r) || Double.isNaN(u) || Double.isNaN(d)) { l = r = u = d = e; }
                double dzdx = exaggeration * (r - l) / (2 * pixM);      // leste
                double dzdy = exaggeration * (u - d) / (2 * pixM);      // norte (linhas crescem para o sul)
                double nx = -dzdx, ny = -dzdy, nz = 1;
                double len = Math.sqrt(nx * nx + ny * ny + nz * nz);
                double shade = Math.max(0, (nx * lx + ny * ly + nz * lz) / len);   // 0..1 (plano = ~0.71)
                double k = (shade - 0.71) * 3.0;                                    // <0 escurece, >0 clareia

                int[] base = hypsometric(e);
                int r8 = clamp(base[0] * (1 + k)), g8 = clamp(base[1] * (1 + k)), b8 = clamp(base[2] * (1 + k));
                int a = clamp(95 + Math.abs(k) * 110);                              // relevo acentuado fica mais opaco
                img.setRGB(i - 1, j - 1, (a << 24) | (r8 << 16) | (g8 << 8) | b8);
            }
        }
    }

    /** Cor por altitude: verde (baixo) -> amarelo -> marrom -> branco (alto). */
    private static int[] hypsometric(double e) {
        double[] stops = {0, 300, 700, 1200, 2000};
        int[][] cols = {{86, 160, 90}, {190, 190, 100}, {176, 130, 80}, {140, 100, 80}, {240, 240, 240}};
        if (e <= stops[0]) return cols[0];
        for (int s = 1; s < stops.length; s++) {
            if (e <= stops[s]) {
                double t = (e - stops[s - 1]) / (stops[s] - stops[s - 1]);
                return new int[]{
                        (int) (cols[s - 1][0] + t * (cols[s][0] - cols[s - 1][0])),
                        (int) (cols[s - 1][1] + t * (cols[s][1] - cols[s - 1][1])),
                        (int) (cols[s - 1][2] + t * (cols[s][2] - cols[s - 1][2]))};
            }
        }
        return cols[cols.length - 1];
    }

    private static int clamp(double v) { return (int) Math.max(0, Math.min(255, v)); }

    private static double pixelLon(int tx, int px, int n) {
        return (tx + px / (double) SIZE) / n * 360.0 - 180.0;
    }

    private static double pixelLat(int ty, int py, int n) {
        double m = Math.PI * (1 - 2 * (ty + py / (double) SIZE) / n);
        return Math.toDegrees(Math.atan(Math.sinh(m)));
    }
}
