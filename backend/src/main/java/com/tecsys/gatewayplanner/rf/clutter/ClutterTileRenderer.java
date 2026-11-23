package com.tecsys.gatewayplanner.rf.clutter;

import javax.imageio.ImageIO;
import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.Ellipse2D;
import java.awt.geom.Path2D;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

/**
 * Desenha árvores e prédios como tiles PNG 256x256 transparentes para sobrepor ao mapa.
 * Em vez de pintar células, desenha ícones pequenos: uma árvore (copa verde e tronco) onde há mata
 * e um prédio (laranja, com janelas) onde há construção. Os ícones ficam numa grade por tile,
 * sempre inteiros (nunca cortados na borda), e crescem um pouco com o zoom.
 */
public final class ClutterTileRenderer {

    public static final int MIN_ZOOM = 12;
    private static final int SIZE = 256;

    private static final Color TREE_CROWN = new Color(46, 160, 67);
    private static final Color TREE_DARK = new Color(27, 110, 45);
    private static final Color TRUNK = new Color(110, 72, 40);
    private static final Color BUILDING = new Color(224, 112, 40);
    private static final Color BUILDING_DARK = new Color(150, 70, 20);
    private static final Color WINDOW = new Color(255, 236, 190);

    private ClutterTileRenderer() {
    }

    public static byte[] png(ClutterProvider clutter, int z, int x, int y) throws IOException {
        BufferedImage img = new BufferedImage(SIZE, SIZE, BufferedImage.TYPE_INT_ARGB);
        int n = 1 << Math.max(0, Math.min(z, 22));
        if (z >= MIN_ZOOM && x >= 0 && y >= 0 && x < n && y < n) {
            Graphics2D g = img.createGraphics();
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
            int icon = iconSize(z);
            int step = icon + (icon >= 15 ? 3 : 2); // ícones quase colados: a camada fica densa como a região de fato é
            for (int by = 0; by + step <= SIZE; by += step) {
                for (int bx = 0; bx + step <= SIZE; bx += step) {
                    int kind = dominantKind(clutter, x, y, n, bx, by, step);
                    if (kind == 1) drawTree(g, bx + (step - icon) / 2.0, by + (step - icon) / 2.0, icon);
                    else if (kind == 2) drawBuilding(g, bx + (step - icon) / 2.0, by + (step - icon) / 2.0, icon);
                }
            }
            g.dispose();
        }
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ImageIO.write(img, "png", bytes);
        return bytes.toByteArray();
    }

    /** Tamanho do ícone em pixels: pequeno no zoom afastado (muitos ícones), maior de perto. */
    static int iconSize(int z) {
        if (z <= 12) return 9;
        if (z == 13) return 10;
        if (z == 14) return 12;
        if (z == 15) return 15;
        if (z == 16) return 19;
        return 24;
    }

    /**
     * O que há no quadradinho (5x5 amostras): 1 = árvore, 2 = prédio, 0 = nada.
     * Prédios são pequenos (um telhado pode ter menos de 20 m), então basta uma amostra para marcar prédio;
     * mata exige um pouco mais, para não pontilhar o mapa com árvores soltas nas bordas.
     */
    private static int dominantKind(ClutterProvider c, int tx, int ty, int n, int bx, int by, int step) {
        int trees = 0, buildings = 0;
        final int K = 5;
        for (int j = 0; j < K; j++) {
            double lat = lat(ty, by + (j + 0.5) * step / K, n);
            for (int i = 0; i < K; i++) {
                int k = c.kindAt(lat, lon(tx, bx + (i + 0.5) * step / K, n));
                if (k == 1) trees++;
                else if (k == 2) buildings++;
            }
        }
        if (buildings >= 1 && buildings * 2 >= trees) return 2;
        if (trees >= 3) return 1;
        return buildings >= 1 ? 2 : 0;
    }

    private static void drawTree(Graphics2D g, double x, double y, int s) {
        double trunkW = Math.max(2, s * 0.16), trunkH = s * 0.28;
        g.setColor(TRUNK);
        g.fill(new RoundRectangle2D.Double(x + (s - trunkW) / 2, y + s - trunkH, trunkW, trunkH, 1, 1));
        double crown = s * 0.82;
        Ellipse2D e = new Ellipse2D.Double(x + (s - crown) / 2, y + 0.02 * s, crown, crown);
        g.setColor(TREE_CROWN);
        g.fill(e);
        g.setColor(TREE_DARK);
        g.setStroke(new BasicStroke(1f));
        g.draw(e);
    }

    private static void drawBuilding(Graphics2D g, double x, double y, int s) {
        double w = s * 0.62, h = s * 0.92;
        double bx = x + (s - w) / 2, by = y + (s - h) / 2;
        g.setColor(BUILDING);
        g.fill(new RoundRectangle2D.Double(bx, by, w, h, 2, 2));
        g.setColor(BUILDING_DARK);
        g.setStroke(new BasicStroke(1f));
        g.draw(new RoundRectangle2D.Double(bx, by, w, h, 2, 2));
        // janelas (só quando o ícone é grande o bastante para mostrá-las)
        if (s >= 13) {
            g.setColor(WINDOW);
            int rows = s >= 17 ? 3 : 2;
            double ww = w * 0.22, wh = h * 0.12;
            for (int r = 0; r < rows; r++) {
                double wy = by + h * (0.16 + r * 0.24);
                g.fill(new java.awt.geom.Rectangle2D.Double(bx + w * 0.2, wy, ww, wh));
                g.fill(new java.awt.geom.Rectangle2D.Double(bx + w * 0.58, wy, ww, wh));
            }
            // porta
            g.setColor(BUILDING_DARK);
            g.fill(new java.awt.geom.Rectangle2D.Double(bx + w * 0.4, by + h * 0.78, w * 0.2, h * 0.22));
        }
    }

    private static double lon(int tx, double px, int n) {
        return (tx + px / SIZE) / n * 360.0 - 180.0;
    }

    private static double lat(int ty, double py, int n) {
        double m = Math.PI * (1 - 2 * (ty + py / SIZE) / n);
        return Math.toDegrees(Math.atan(Math.sinh(m)));
    }
}
