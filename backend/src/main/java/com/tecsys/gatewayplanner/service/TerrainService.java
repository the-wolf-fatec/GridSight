package com.tecsys.gatewayplanner.service;

import com.tecsys.gatewayplanner.rf.terrain.SrtmTerrainProvider;
import com.tecsys.gatewayplanner.rf.terrain.TerrainProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.zip.GZIPInputStream;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Fornece o relevo (arquivos SRTM .hgt) para o cálculo de cobertura.
 *
 * Onde procura (usa a primeira pasta que tiver .hgt):
 *   1. gridsight.terrain.dir (application.properties) ou a variável TERRAIN_DIR
 *   2. ./terrain (backend/terrain), ./backend/terrain, ../backend/terrain, ../frontend/terrain, ../terrain (e uma subpasta de cada),
 *      e a pasta fixa ~/gridsight-terrain (C:\Users\voce\gridsight-terrain)
 *   3. se ainda não achou: varre o projeto inteiro (a pasta acima do backend), em até 6 níveis,
 *      e usa a pasta com mais .hgt
 *
 * A busca é refeita sempre que ainda não há relevo (ao calcular, ao atualizar o status),
 * então copiar os arquivos DEPOIS de subir o backend também funciona.
 */
@Service
public class TerrainService {

    private static final Logger log = LoggerFactory.getLogger(TerrainService.class);
    private static final Set<String> SKIP = Set.of("node_modules", ".git", "target", "build", ".dart_tool", ".idea", ".gradle");

    private final String configured;
    private volatile Path dir;
    private volatile SrtmTerrainProvider provider = new SrtmTerrainProvider(Path.of("./terrain").toAbsolutePath().normalize(), false);
    private volatile List<String> searched = List.of();
    private volatile int compressedFound;

    private static final String SKADI = System.getProperty("gridsight.terrain.skadi", "https://elevation-tiles-prod.s3.amazonaws.com/skadi/");
    private static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(20))
            .followRedirects(HttpClient.Redirect.NORMAL).build();

    private final boolean autoDownload;
    private final boolean fullResolution;
    private final long maxWaitMs;
    private final ExecutorService pool = Executors.newFixedThreadPool(6, r -> {
        Thread t = new Thread(r, "terrain-download");
        t.setDaemon(true);
        return t;
    });
    private final Map<String, CompletableFuture<Boolean>> inflight = new ConcurrentHashMap<>();
    private final Set<String> noData = ConcurrentHashMap.newKeySet(); // oceano / fora da cobertura (HTTP 403/404)

    public TerrainService(@Value("${gridsight.terrain.dir:}") String configured,
                          @Value("${gridsight.terrain.auto-download:true}") boolean autoDownload,
                          @Value("${gridsight.terrain.full-resolution:false}") boolean fullResolution,
                          @Value("${gridsight.terrain.max-wait-seconds:25}") long maxWaitSeconds) {
        this.configured = configured == null ? "" : configured.trim();
        this.autoDownload = autoDownload;
        this.fullResolution = fullResolution;
        this.maxWaitMs = Math.max(0, maxWaitSeconds) * 1000L;
        resolve(true);
    }

    /** Resultado de {@link #ensureFor}: quantos ladrilhos eram necessários, baixados agora, com falha e ainda em andamento. */
    public record Prefetch(int needed, int downloaded, int failed, int pending) {
        public String warning() {
            if (pending > 0) {
                return "O relevo de " + pending + " ladrilho(s) está sendo baixado em segundo plano; nessas áreas o cálculo usou só a distância. "
                        + "Rode de novo em alguns minutos (acompanhe em /api/planning/terrain-status).";
            }
            if (failed > 0) {
                return "Não consegui baixar o relevo de " + failed + " ladrilho(s). O computador do backend precisa de acesso à internet "
                        + "(ou copie os .hgt para a pasta 'terrain').";
            }
            if (downloaded > 0) return "Relevo baixado automaticamente: " + downloaded + " ladrilho(s) novo(s).";
            return null;
        }
    }

    /**
     * Garante que os ladrilhos SRTM da região dos pontos (com folga do alcance) existam em disco, baixando os que faltam
     * da cópia pública da AWS (sem login). Espera só até {@code gridsight.terrain.max-wait-seconds} (padrão 25 s) para o cálculo
     * não travar; o que não terminar continua em segundo plano e entra no próximo cálculo.
     *
     * @param points pares {lat, lon}
     */
    public Prefetch ensureFor(Collection<double[]> points, double rangeKm) {
        if (!autoDownload || points == null || points.isEmpty()) return new Prefetch(0, 0, 0, 0);
        Path target = downloadDir();
        double m = Math.min(100, Math.max(0.05, rangeKm)) / 100.0;
        Set<String> need = new LinkedHashSet<>();
        Set<Long> seen = new HashSet<>();
        for (double[] p : points) {
            if (p == null || Double.isNaN(p[0]) || Double.isNaN(p[1]) || Math.abs(p[0]) > 59 || Math.abs(p[1]) > 179) continue;
            int la0 = (int) Math.floor(p[0] - m), la1 = (int) Math.floor(p[0] + m);
            int lo0 = (int) Math.floor(p[1] - m), lo1 = (int) Math.floor(p[1] + m);
            for (int la = la0; la <= la1; la++) {
                for (int lo = lo0; lo <= lo1; lo++) {
                    if (seen.add(((long) (la + 90) << 16) | (lo + 180))) {
                        need.add(SrtmTerrainProvider.tileName(la + 0.5, lo + 0.5));
                    }
                }
            }
        }
        List<CompletableFuture<Boolean>> futures = new ArrayList<>();
        for (String name : need) {
            if (noData.contains(name) || Files.exists(target.resolve(name + ".hgt"))) continue;
            futures.add(inflight.compute(name, (k, old) -> old != null && !old.isDone() ? old
                    : CompletableFuture.supplyAsync(() -> downloadTile(k, target), pool)));
        }
        if (futures.isEmpty()) return new Prefetch(need.size(), 0, 0, 0);
        log.info("Relevo: baixando {} ladrilho(s) que faltam (de {} necessários) para {}", futures.size(), need.size(), target);

        long deadline = System.currentTimeMillis() + maxWaitMs;
        int ok = 0, failed = 0, pending = 0;
        for (CompletableFuture<Boolean> f : futures) {
            try {
                boolean done = f.get(Math.max(1, deadline - System.currentTimeMillis()), TimeUnit.MILLISECONDS);
                if (done) ok++;
                else failed++;
            } catch (TimeoutException e) {
                pending++;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                pending++;
            } catch (Exception e) {
                failed++;
            }
        }
        // tiles de oceano (sem dado) não contam como falha
        failed = Math.max(0, failed - (int) need.stream().filter(noData::contains).count());
        if (ok > 0) refreshProvider(target);
        return new Prefetch(need.size(), ok, failed, pending);
    }

    private Path downloadDir() {
        Path d = dir != null ? dir : Path.of(configured.isBlank() ? "./terrain" : configured);
        return d.toAbsolutePath().normalize();
    }

    private synchronized void refreshProvider(Path target) {
        this.dir = target;
        this.provider = new SrtmTerrainProvider(target, false);
        this.knownCount = countHgt(target);
        log.info("Relevo: agora {} arquivo(s) .hgt em {}", knownCount, target);
    }

    /** Baixa um ladrilho (gz), grava como .hgt (versão leve de ~90 m, salvo full-resolution=true). */
    private boolean downloadTile(String name, Path target) {
        String url = SKADI + name.substring(0, 3) + "/" + name + ".hgt.gz";
        String err = "";
        for (int attempt = 1; attempt <= 3; attempt++) {
            Path tmp = target.resolve(name + ".hgt.part");
            try {
                Files.createDirectories(target);
                HttpRequest rq = HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofMinutes(4))
                        .header("User-Agent", "GridSight/1.0").GET().build();
                HttpResponse<InputStream> resp = HTTP.send(rq, HttpResponse.BodyHandlers.ofInputStream());
                if (resp.statusCode() == 403 || resp.statusCode() == 404) {
                    resp.body().close();
                    noData.add(name);
                    log.info("Relevo: sem dado para {} (HTTP {}), provavelmente oceano", name, resp.statusCode());
                    return false;
                }
                if (resp.statusCode() != 200) {
                    resp.body().close();
                    err = "HTTP " + resp.statusCode();
                    Thread.sleep(2000L * attempt);
                    continue;
                }
                byte[] raw;
                try (InputStream in = new GZIPInputStream(resp.body())) {
                    raw = in.readAllBytes();
                }
                final int big = 3601, small = 1201;
                if (raw.length == (long) big * big * 2 && !fullResolution) {
                    byte[] out = new byte[small * small * 2];
                    for (int r = 0; r < small; r++) {
                        for (int c = 0; c < small; c++) {
                            int src = ((r * 3) * big + c * 3) * 2;
                            int dst = (r * small + c) * 2;
                            out[dst] = raw[src];
                            out[dst + 1] = raw[src + 1];
                        }
                    }
                    raw = out;
                } else if (raw.length != (long) big * big * 2 && raw.length != (long) small * small * 2) {
                    err = "tamanho inesperado (" + raw.length + " bytes)";
                    continue;
                }
                Files.write(tmp, raw);
                Files.move(tmp, target.resolve(name + ".hgt"), StandardCopyOption.REPLACE_EXISTING);
                log.info("Relevo: ladrilho {} baixado ({} MB)", name, String.format("%.1f", raw.length / 1e6));
                return true;
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return false;
            } catch (IOException | RuntimeException e) {
                err = String.valueOf(e);
                try {
                    Files.deleteIfExists(tmp);
                } catch (IOException ignored) {
                }
                try {
                    Thread.sleep(2000L * attempt);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    return false;
                }
            }
        }
        log.warn("Relevo: não consegui baixar {}: {}", url, err);
        return false;
    }

    private volatile int knownCount = -1;
    private volatile long lastCheck = 0;

    /**
     * Relevo atual. Se ainda não havia arquivos, procura de novo; se a quantidade de .hgt
     * mudou (arquivo copiado depois de subir), recria o leitor para enxergar os novos.
     */
    public TerrainProvider provider() {
        if (dir == null) resolve(false);
        long now = System.currentTimeMillis();
        if (dir != null && now - lastCheck > 3000) {
            lastCheck = now;
            int count = countHgt(dir);
            if (knownCount >= 0 && count != knownCount) {
                provider = new SrtmTerrainProvider(dir, false);
                log.info("Relevo: agora {} arquivo(s) .hgt em {}", count, dir);
            }
            knownCount = count;
        }
        return provider;
    }

    /** Situação do relevo (GET /api/planning/terrain-status). Refaz a busca se ainda não achou nada. */
    public Map<String, Object> status() {
        provider(); // refaz a busca e percebe arquivos novos
        List<String> tiles = dir == null ? List.of() : listHgt(dir);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("directory", dir != null ? dir.toString() : (searched.isEmpty() ? "" : searched.get(0)));
        m.put("tileCount", tiles.size());
        m.put("tiles", tiles);
        m.put("searchedDirectories", searched);
        m.put("ok", !tiles.isEmpty());
        m.put("downloading", inflight.values().stream().filter(f -> !f.isDone()).count());
        m.put("noDataTiles", noData.size());
        m.put("hint", hint(tiles.isEmpty()));
        return m;
    }

    private String hint(boolean empty) {
        if (!empty) return "";
        if (compressedFound > 0) {
            return "Achei " + compressedFound + " arquivo(s) compactado(s) (.zip/.gz/.rar): descompacte para .hgt.";
        }
        return autoDownload
                ? "O relevo é baixado automaticamente ao calcular (precisa de internet no computador do backend)."
                : "Copie os arquivos .hgt para a pasta backend/terrain e clique em atualizar.";
    }

    private synchronized void resolve(boolean first) {
        List<Path> candidates = new ArrayList<>();
        if (!configured.isBlank()) candidates.add(Path.of(configured));
        candidates.add(Path.of("./terrain"));            // backend/terrain (padrão)
        candidates.add(Path.of("./backend/terrain"));    // rodando a partir da pasta do projeto
        candidates.add(Path.of("../backend/terrain"));
        candidates.add(Path.of("../frontend/terrain"));
        candidates.add(Path.of("../terrain"));
        candidates.add(Path.of("./frontend/terrain"));
        // Pasta fixa, fora do projeto: funciona de qualquer cópia do projeto (ex.: C:\Users\voce\gridsight-terrain)
        candidates.add(Path.of(System.getProperty("user.home", "."), "gridsight-terrain"));

        List<String> tried = new ArrayList<>();
        Path chosen = null;
        for (Path c : candidates) {
            Path abs = c.toAbsolutePath().normalize();
            tried.add(abs.toString());
            if (chosen != null) continue;
            if (countHgt(abs) > 0) {
                chosen = abs;
                continue;
            }
            for (Path sub : subdirectories(abs)) {
                if (countHgt(sub) > 0) {
                    chosen = sub;
                    break;
                }
            }
        }

        int compressed = 0;
        if (chosen == null) {
            Path root = Path.of("..").toAbsolutePath().normalize();
            tried.add(root + " (varredura em até 6 níveis)");
            Map<Path, Integer> found = new LinkedHashMap<>();
            for (Path start : List.of(root, Path.of(".").toAbsolutePath().normalize())) {
                compressed += scan(start, found);
            }
            chosen = found.entrySet().stream().max(Map.Entry.comparingByValue()).map(Map.Entry::getKey).orElse(null);
        }
        this.searched = tried;
        this.compressedFound = compressed;

        if (chosen == null) {
            if (first) {
                log.warn("Relevo: NENHUM arquivo .hgt encontrado. Procurei em: {}. Copie os .hgt para backend/terrain "
                        + "(ou defina gridsight.terrain.dir). Sem eles o app calcula só por distância.", tried);
            }
            return;
        }
        if (!chosen.equals(this.dir)) {
            this.dir = chosen;
            this.provider = new SrtmTerrainProvider(chosen, false);
            log.info("Relevo: {} arquivo(s) .hgt em {}", countHgt(chosen), chosen);
        }
    }

    /** Varre {@code start} (profundidade máx. 6) e conta .hgt por pasta; devolve quantos compactados viu. */
    private static int scan(Path start, Map<Path, Integer> found) {
        int[] compressed = {0};
        try (Stream<Path> s = Files.walk(start, 6)) {
            s.filter(p -> {
                for (Path part : start.relativize(p)) {
                    if (SKIP.contains(part.toString())) return false;
                }
                return true;
            }).forEach(p -> {
                String n = p.getFileName() == null ? "" : p.getFileName().toString().toLowerCase();
                if (n.endsWith(".hgt")) {
                    found.merge(p.getParent(), 1, Integer::sum);
                } else if (n.endsWith(".hgt.gz") || n.endsWith(".hgt.zip") || n.endsWith(".rar")) {
                    compressed[0]++;
                }
            });
        } catch (IOException | RuntimeException ignored) {
        }
        return compressed[0];
    }

    private static List<Path> subdirectories(Path d) {
        if (!Files.isDirectory(d)) return List.of();
        try (Stream<Path> s = Files.list(d)) {
            return s.filter(Files::isDirectory).sorted().collect(Collectors.toList());
        } catch (IOException e) {
            return List.of();
        }
    }

    private static int countHgt(Path d) {
        return listHgt(d).size();
    }

    private static List<String> listHgt(Path d) {
        if (d == null || !Files.isDirectory(d)) return List.of();
        try (Stream<Path> s = Files.list(d)) {
            return s.map(p -> p.getFileName().toString())
                    .filter(n -> n.toLowerCase().endsWith(".hgt"))
                    .sorted()
                    .collect(Collectors.toList());
        } catch (IOException e) {
            return List.of();
        }
    }
}
