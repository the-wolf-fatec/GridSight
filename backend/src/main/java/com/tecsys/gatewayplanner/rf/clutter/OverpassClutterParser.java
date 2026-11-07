package com.tecsys.gatewayplanner.rf.clutter;

import com.fasterxml.jackson.databind.JsonNode;

/**
 * Lê a resposta JSON do Overpass (OpenStreetMap) e preenche um {@link ClutterTile}.
 *
 * - Florestas e matas (natural=wood, landuse=forest): altura típica de copa, {@link #TREE_HEIGHT_M}.
 * - Prédios (building=*): usa a tag "height"; senão "building:levels" x 3,2 m; senão {@link #DEFAULT_BUILDING_M}.
 *
 * Aceita elementos com "geometry" (polígono completo) ou só "bounds" (caixa do prédio, resposta "out bb").
 * Buracos de multipolígonos (clareiras) são ignorados: o resultado é conservador.
 */
public final class OverpassClutterParser {

    public static final int TREE_HEIGHT_M = 15;
    public static final int DEFAULT_BUILDING_M = 8;

    private OverpassClutterParser() {
    }

    public static int heightFor(JsonNode tags) {
        if (tags == null || tags.isMissingNode()) return 0;
        String building = text(tags, "building");
        if (building != null && !building.equals("no")) {
            Double h = number(text(tags, "height"));
            if (h != null) return clamp(h);
            Double levels = number(text(tags, "building:levels"));
            if (levels != null) return clamp(levels * 3.2);
            return DEFAULT_BUILDING_M;
        }
        if ("wood".equals(text(tags, "natural")) || "forest".equals(text(tags, "landuse"))) return TREE_HEIGHT_M;
        return 0;
    }

    /** true = mata/floresta; false = prédio. */
    public static boolean isTree(JsonNode tags) {
        return tags != null && ("wood".equals(text(tags, "natural")) || "forest".equals(text(tags, "landuse")))
                && (text(tags, "building") == null);
    }

    public static void parse(JsonNode root, ClutterTile tile) {
        JsonNode elements = root.path("elements");
        if (!elements.isArray()) return;
        for (JsonNode el : elements) {
            int height = heightFor(el.path("tags"));
            if (height <= 0) continue;
            boolean tree = isTree(el.path("tags"));
            String type = el.path("type").asText();
            if ("way".equals(type)) {
                fillWay(el, height, tree, tile);
            } else if ("relation".equals(type)) {
                for (JsonNode m : el.path("members")) {
                    if ("outer".equals(m.path("role").asText()) && m.has("geometry")) fillGeometry(m.get("geometry"), height, tree, tile);
                }
                JsonNode b = el.path("bounds");
                if (!el.path("members").isArray() && b.isObject()) fillBounds(b, height, tree, tile);
            }
        }
    }

    private static void fillWay(JsonNode el, int height, boolean tree, ClutterTile tile) {
        if (el.has("geometry")) fillGeometry(el.get("geometry"), height, tree, tile);
        else if (el.path("bounds").isObject()) fillBounds(el.get("bounds"), height, tree, tile);
    }

    private static void fillGeometry(JsonNode geom, int height, boolean tree, ClutterTile tile) {
        int n = geom.size();
        if (n < 3) return;
        double[] lat = new double[n], lon = new double[n];
        for (int i = 0; i < n; i++) {
            lat[i] = geom.get(i).path("lat").asDouble();
            lon[i] = geom.get(i).path("lon").asDouble();
        }
        tile.fillPolygon(lat, lon, height, tree);
    }

    private static void fillBounds(JsonNode b, int height, boolean tree, ClutterTile tile) {
        tile.fillRect(b.path("minlat").asDouble(), b.path("minlon").asDouble(),
                b.path("maxlat").asDouble(), b.path("maxlon").asDouble(), height, tree);
    }

    private static String text(JsonNode tags, String key) {
        JsonNode v = tags.get(key);
        return v == null || v.isNull() ? null : v.asText();
    }

    private static Double number(String s) {
        if (s == null) return null;
        try {
            return Double.parseDouble(s.replaceAll("[^0-9.,-]", "").replace(',', '.'));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static int clamp(double h) {
        return (int) Math.max(3, Math.min(127, Math.round(h)));
    }
}
