package com.tecsys.gatewayplanner.service;

import com.tecsys.gatewayplanner.repository.AssetRepository;
import com.tecsys.gatewayplanner.repository.CandidateSiteRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Ao subir o backend, baixa em segundo plano o relevo (SRTM) de todas as regiões que têm ativos ou
 * candidatos no banco. Assim a primeira otimização já encontra os arquivos prontos.
 * Desligado por padrão (gridsight.terrain.warmup=true liga); com dados do Brasil inteiro são centenas de ladrilhos.
 */
@Component
public class TerrainWarmup {

    private static final Logger log = LoggerFactory.getLogger(TerrainWarmup.class);

    private final TerrainService terrain;
    private final AssetRepository assets;
    private final CandidateSiteRepository candidates;
    private final boolean enabled;

    public TerrainWarmup(TerrainService terrain, AssetRepository assets, CandidateSiteRepository candidates,
                         @Value("${gridsight.terrain.warmup:false}") boolean enabled) {
        this.terrain = terrain;
        this.assets = assets;
        this.candidates = candidates;
        this.enabled = enabled;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void start() {
        if (!enabled) return;
        Thread t = new Thread(this::run, "terrain-warmup");
        t.setDaemon(true);
        t.start();
    }

    private void run() {
        try {
            Set<Long> seen = new LinkedHashSet<>();
            List<double[]> pts = new ArrayList<>();
            collect(assets.findTiles(), seen, pts);
            collect(candidates.findTiles(), seen, pts);
            if (pts.isEmpty()) return;
            log.info("Relevo: verificando {} ladrilho(s) das regiões dos seus dados (baixa só o que faltar)", pts.size());
            TerrainService.Prefetch r = terrain.ensureFor(pts, 0.05);
            log.info("Relevo (aquecimento): {}", r);
        } catch (RuntimeException e) {
            log.warn("Relevo: aquecimento falhou: {}", e.toString());
        }
    }

    private static void collect(List<Object[]> rows, Set<Long> seen, List<double[]> out) {
        for (Object[] r : rows) {
            if (r == null || r.length < 2 || r[0] == null || r[1] == null) continue;
            int la = ((Number) r[0]).intValue(), lo = ((Number) r[1]).intValue();
            if (seen.add(((long) (la + 90) << 16) | (lo + 180))) out.add(new double[]{la + 0.5, lo + 0.5});
        }
    }
}
