package com.tecsys.gatewayplanner.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.tecsys.gatewayplanner.planning.PlanRequest;
import com.tecsys.gatewayplanner.rf.clutter.ClutterProvider;
import com.tecsys.gatewayplanner.rf.clutter.ClutterTile;
import com.tecsys.gatewayplanner.rf.clutter.OverpassClutterParser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Árvores e prédios (obstáculos que o relevo SRTM não mostra), vindos do OpenStreetMap via Overpass.
 *
 * Antes de cada cálculo, {@link #prepare} garante que os ladrilhos de ~5,5 km da região estão na
 * memória: lê do cache em disco (pasta gridsight.clutter.dir, padrão ./clutter) ou baixa do Overpass
 * (só na primeira vez; depois fica em disco e funciona sem internet). Durante o cálculo,
 * {@link #heightM} só consulta a memória.
 */
@Service
public class ClutterService implements ClutterProvider {

    private static final Logger log = LoggerFactory.getLogger(ClutterService.class);
    private static final int MAX_TILES = 60;
    private static final String CACHE_VERSION = "v2";

    private final Path dir;
    private final String overpassUrl;
    private final Map<Long, ClutterTile> tiles = new ConcurrentHashMap<>();
    private final ObjectMapper mapper = new ObjectMapper();
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build();
    private long lastRequestAt = 0;

    public ClutterService(@Value("${gridsight.clutter.dir:./clutter}") String dir,
                          @Value("${gridsight.clutter.overpass-url:https://overpass-api.de/api/interpreter}") String overpassUrl) {
        this.dir = Path.of(dir).toAbsolutePath().normalize();
        this.overpassUrl = overpassUrl;
    }

    @Override
    public double heightM(double lat, double lon) {
        ClutterTile t = tiles.get(ClutterTile.key(ClutterTile.tileIndex(lat), ClutterTile.tileIndex(lon)));
        return t == null ? 0 : t.heightAt(lat, lon);
    }

    @Override
    public int kindAt(double lat, double lon) {
        ClutterTile t = tiles.get(ClutterTile.key(ClutterTile.tileIndex(lat), ClutterTile.tileIndex(lon)));
        return t == null ? 0 : t.kindAt(lat, lon);
    }

    private final Map<Long, Long> failedAt = new ConcurrentHashMap<>();

    /**
     * Garante os ladrilhos que cobrem uma área do mapa (para desenhar a camada): lê do cache em disco
     * ou baixa do OpenStreetMap. Falhas ficam em espera por 10 min para não insistir no servidor.
     */
    public synchronized void ensureArea(double minLat, double minLon, double maxLat, double maxLon) {
        for (int i = ClutterTile.tileIndex(minLat); i <= ClutterTile.tileIndex(maxLat); i++) {
            for (int j = ClutterTile.tileIndex(minLon); j <= ClutterTile.tileIndex(maxLon); j++) {
                long key = ClutterTile.key(i, j);
                if (tiles.containsKey(key)) continue;
                Long f = failedAt.get(key);
                if (f != null && System.currentTimeMillis() - f < 600_000) continue;
                try {
                    ClutterTile t = readCache(i, j);
                    if (t == null) {
                        t = download(i, j);
                        writeCache(t);
                    }
                    tiles.put(key, t);
                } catch (Exception e) {
                    failedAt.put(key, System.currentTimeMillis());
                    log.warn("Obstáculos (camada do mapa): falha no ladrilho {},{}: {}", i, j, e.toString());
                }
            }
        }
    }

    /**
     * Carrega os ladrilhos ao redor dos ativos e candidatos do pedido.
     * @return true se há dado de obstáculos para pelo menos parte da região
     */
    public synchronized boolean prepare(PlanRequest req, List<String> warnings) {
        Set<Long> wanted = new LinkedHashSet<>();
        List<int[]> order = new java.util.ArrayList<>();
        for (PlanRequest.Group g : req.groups) {
            if (g.assets != null) for (PlanRequest.Site s : g.assets) addAround(s, wanted, order);
            if (g.candidates != null) for (PlanRequest.Site s : g.candidates) addAround(s, wanted, order);
        }
        if (order.isEmpty()) return false;
        boolean truncated = order.size() > MAX_TILES;
        int failed = 0, ok = 0;
        String firstError = null;
        for (int k = 0; k < Math.min(MAX_TILES, order.size()); k++) {
            int[] ij = order.get(k);
            long key = ClutterTile.key(ij[0], ij[1]);
            if (tiles.containsKey(key)) {
                ok++;
                continue;
            }
            try {
                ClutterTile t = readCache(ij[0], ij[1]);
                if (t == null) {
                    t = download(ij[0], ij[1]);
                    writeCache(t);
                }
                tiles.put(key, t);
                ok++;
            } catch (Exception e) {
                failed++;
                if (firstError == null) firstError = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
                log.warn("Obstáculos: falha no ladrilho {},{}: {}", ij[0], ij[1], e.toString());
            }
        }
        if (failed > 0) {
            warnings.add("Não consegui baixar árvores e prédios (OpenStreetMap) de " + failed + " trecho(s) da região (" + firstError
                    + "). Nessas partes o cálculo ficou sem esses obstáculos; tente de novo mais tarde.");
        }
        if (truncated) {
            warnings.add("A região é grande: árvores e prédios foram considerados só em parte dela (limite de " + MAX_TILES + " trechos de ~5 km).");
        }
        return ok > 0;
    }

    /** Ladrilho do ponto e os 8 vizinhos (os enlaces atravessam ladrilhos ao lado). */
    private void addAround(PlanRequest.Site s, Set<Long> seen, List<int[]> order) {
        int i0 = ClutterTile.tileIndex(s.lat), j0 = ClutterTile.tileIndex(s.lon);
        for (int di = -1; di <= 1; di++) {
            for (int dj = -1; dj <= 1; dj++) {
                if (seen.add(ClutterTile.key(i0 + di, j0 + dj))) order.add(new int[]{i0 + di, j0 + dj});
            }
        }
    }

    private Path cacheFile(int i, int j) {
        return dir.resolve("t_" + i + "_" + j + "_" + CACHE_VERSION + ".bin");
    }

    private ClutterTile readCache(int i, int j) {
        try {
            Path f = cacheFile(i, j);
            if (!Files.isRegularFile(f)) return null;
            byte[] data = Files.readAllBytes(f);
            return data.length == ClutterTile.N * ClutterTile.N ? new ClutterTile(i, j, data) : null;
        } catch (Exception e) {
            return null;
        }
    }

    private void writeCache(ClutterTile t) {
        try {
            Files.createDirectories(dir);
            Files.write(cacheFile(t.tileI, t.tileJ), t.data());
        } catch (Exception e) {
            log.warn("Obstáculos: não consegui gravar o cache em {}: {}", dir, e.toString());
        }
    }

    private ClutterTile download(int i, int j) throws Exception {
        double s = i * ClutterTile.TILE_DEG, w = j * ClutterTile.TILE_DEG;
        double n = s + ClutterTile.TILE_DEG, e = w + ClutterTile.TILE_DEG;
        String box = String.format(java.util.Locale.ROOT, "%.5f,%.5f,%.5f,%.5f", s, w, n, e);
        ClutterTile tile = new ClutterTile(i, j);
        // 1) matas e florestas, com o contorno completo
        String veg = "[out:json][timeout:90];(way[\"natural\"=\"wood\"](" + box + ");way[\"landuse\"=\"forest\"](" + box + ");"
                + "relation[\"natural\"=\"wood\"](" + box + ");relation[\"landuse\"=\"forest\"](" + box + "););out geom;";
        OverpassClutterParser.parse(query(veg), tile);
        // 2) prédios: só a caixa de cada um (resposta bem menor que o contorno)
        String bld = "[out:json][timeout:120];way[\"building\"](" + box + ");out tags bb;";
        OverpassClutterParser.parse(query(bld), tile);
        log.info("Obstáculos: ladrilho {},{} baixado do OpenStreetMap", i, j);
        return tile;
    }

    private JsonNode query(String ql) throws Exception {
        long wait = 1500 - (System.currentTimeMillis() - lastRequestAt); // educação com o servidor público
        if (wait > 0) Thread.sleep(wait);
        HttpRequest rq = HttpRequest.newBuilder(URI.create(overpassUrl))
                .timeout(Duration.ofSeconds(150))
                .header("User-Agent", "GridSight-Tecsys-FatecSJC/1.0 (academic project)")
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString("data=" + URLEncoder.encode(ql, StandardCharsets.UTF_8)))
                .build();
        HttpResponse<java.io.InputStream> r = http.send(rq, HttpResponse.BodyHandlers.ofInputStream());
        lastRequestAt = System.currentTimeMillis();
        if (r.statusCode() != 200) {
            r.body().close();
            throw new IllegalStateException("Overpass respondeu HTTP " + r.statusCode());
        }
        try (java.io.InputStream in = r.body()) {
            return mapper.readTree(in);
        }
    }
}
