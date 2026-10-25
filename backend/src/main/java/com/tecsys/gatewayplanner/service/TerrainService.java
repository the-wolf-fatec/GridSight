package com.tecsys.gatewayplanner.service;

import com.tecsys.gatewayplanner.rf.terrain.SrtmTerrainProvider;
import com.tecsys.gatewayplanner.rf.terrain.TerrainProvider;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Fornece o relevo (arquivos SRTM .hgt) para o cálculo de cobertura.
 *
 * Onde procura (usa a primeira pasta que tiver .hgt):
 *   1. gridsight.terrain.dir (application.properties) ou a variável TERRAIN_DIR
 *   2. ./terrain (backend/terrain), ./backend/terrain, ../backend/terrain, ../frontend/terrain, ../terrain (e uma subpasta de cada)
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

    public TerrainService(@Value("${gridsight.terrain.dir:}") String configured) {
        this.configured = configured == null ? "" : configured.trim();
        resolve(true);
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
        m.put("hint", hint(tiles.isEmpty()));
        return m;
    }

    private String hint(boolean empty) {
        if (!empty) return "";
        if (compressedFound > 0) {
            return "Achei " + compressedFound + " arquivo(s) compactado(s) (.zip/.gz/.rar): descompacte para .hgt.";
        }
        return "Copie os arquivos .hgt para a pasta backend/terrain e clique em atualizar.";
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
