package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.rf.terrain.RegionMask;
import com.tecsys.gatewayplanner.rf.terrain.StateBoundary;
import com.tecsys.gatewayplanner.rf.terrain.TerrainTileRenderer;
import com.tecsys.gatewayplanner.rf.terrain.TileClip;
import com.tecsys.gatewayplanner.service.TerrainService;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Tiles de RELEVO (sombreado + cor de terra por altitude) para sobrepor ao mapa.
 *
 *   POST /api/terrain/regions                     registra a região escolhida (pontos da rede) e devolve um id
 *   GET  /api/terrain/tiles/{z}/{x}/{y}.png       relevo recortado pela região (?r=id) ou, sem id, pelo estado de SP
 */
@RestController
public class TerrainTileController {

    private static final int MAX_REGIONS = 24;

    private final TerrainService terrainService;
    private final StateBoundary boundary = StateBoundary.loadSp();

    /** Regiões registradas (as mais antigas saem quando passa de {@link #MAX_REGIONS}). */
    private final Map<String, RegionMask> regions = new LinkedHashMap<>();

    public TerrainTileController(TerrainService terrainService) {
        this.terrainService = terrainService;
    }

    /** Corpo do POST: pontos {lat, lon} da rede selecionada e o quanto o relevo sobra em volta deles. */
    public static class RegionRequest {
        public List<double[]> points = new ArrayList<>();
        public double radiusKm = 8;
    }

    @PostMapping("/api/terrain/regions")
    public Map<String, Object> registerRegion(@RequestBody RegionRequest request) {
        if (request == null || request.points == null || request.points.isEmpty()) {
            throw new IllegalArgumentException("Envie ao menos um ponto da rede.");
        }
        RegionMask mask = RegionMask.of(request.points, request.radiusKm);
        if (mask.size() == 0) throw new IllegalArgumentException("Nenhum ponto válido na região.");
        String id = mask.id();
        synchronized (regions) {
            regions.remove(id);
            regions.put(id, mask);
            while (regions.size() > MAX_REGIONS) {
                String oldest = regions.keySet().iterator().next();
                regions.remove(oldest);
            }
        }
        return Map.of("id", id, "points", mask.size());
    }

    @GetMapping("/api/terrain/tiles/{z}/{x}/{y}.png")
    public ResponseEntity<byte[]> tile(@PathVariable int z, @PathVariable int x, @PathVariable int y,
                                       @RequestParam(name = "r", required = false) String regionId) throws IOException {
        TileClip clip = boundary;
        if (regionId != null && !regionId.isBlank()) {
            RegionMask mask;
            synchronized (regions) {
                mask = regions.get(regionId);
            }
            if (mask != null) clip = mask; // id desconhecido (ex.: backend reiniciou): cai para o contorno de SP
        }
        // provider() é refeito a cada pedido: pega arquivos copiados depois de subir o backend
        byte[] png = TerrainTileRenderer.png(terrainService.provider(), clip, z, x, y);
        return ResponseEntity.ok()
                .contentType(MediaType.IMAGE_PNG)
                .cacheControl(CacheControl.maxAge(Duration.ofMinutes(10)).cachePublic())
                .body(png);
    }
}
