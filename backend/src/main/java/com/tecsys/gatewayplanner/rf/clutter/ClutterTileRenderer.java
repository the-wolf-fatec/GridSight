package com.tecsys.gatewayplanner.rf.clutter;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

/** Desenha árvores (verde) e prédios (laranja) como tiles PNG 256x256 transparentes para sobrepor ao mapa. */
public final class ClutterTileRenderer {

    public static final int MIN_ZOOM = 12;
    private static final int SIZE = 256;
    private static final int TREE = (150 << 24) | (46 << 16) | (160 << 8) | 67;
    private static final int BUILDING = (210 << 24) | (224 << 16) | (112 << 8) | 40;

    private ClutterTileRenderer() {
    }

    public static byte[] png(ClutterProvider clutter, int z, int x, int y) throws IOException {
        BufferedImage img = new BufferedImage(SIZE, SIZE, BufferedImage.TYPE_INT_ARGB);
        int n = 1 << Math.max(0, Math.min(z, 22));
        if (z >= MIN_ZOOM && x >= 0 && y >= 0 && x < n && y < n) {
            for (int j = 0; j < SIZE; j++) {
                double lat = lat(y, j + 0.5, n);
                for (int i = 0; i < SIZE; i++) {
                    int kind = clutter.kindAt(lat, lon(x, i + 0.5, n));
                    if (kind == 1) img.setRGB(i, j, TREE);
                    else if (kind == 2) img.setRGB(i, j, BUILDING);
                }
            }
        }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ImageIO.write(img, "png", bytes);
        return bytes.toByteArray();
    }

    private static double lon(int tx, double px, int n) {
        return (tx + px / SIZE) / n * 360.0 - 180.0;
    }

    private static double lat(int ty, double py, int n) {
        double m = Math.PI * (1 - 2 * (ty + py / SIZE) / n);
        return Math.toDegrees(Math.atan(Math.sinh(m)));
    }
}
