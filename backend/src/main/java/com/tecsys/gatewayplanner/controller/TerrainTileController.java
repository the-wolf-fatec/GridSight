package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.rf.terrain.StateBoundary;
import com.tecsys.gatewayplanner.rf.terrain.TerrainTileRenderer;
import com.tecsys.gatewayplanner.service.TerrainService;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.time.Duration;

/**
 * Tiles de RELEVO para sobrepor ao mapa: sombreado + cor por altitude, gerados dos MESMOS
 * dados usados no cálculo de cobertura e recortados pelo contorno do estado de São Paulo.
 *
 * GET /api/terrain/tiles/{z}/{x}/{y}.png  (PNG 256x256 com transparência)
 */
@RestController
public class TerrainTileController {

    private final TerrainService terrainService;
    private final StateBoundary boundary = StateBoundary.loadSp();

    public TerrainTileController(TerrainService terrainService) {
        this.terrainService = terrainService;
    }

    @GetMapping("/api/terrain/tiles/{z}/{x}/{y}.png")
    public ResponseEntity<byte[]> tile(@PathVariable int z, @PathVariable int x, @PathVariable int y) throws IOException {
        // provider() é refeito a cada pedido: pega arquivos copiados depois de subir o backend
        byte[] png = TerrainTileRenderer.png(terrainService.provider(), boundary, z, x, y);
        return ResponseEntity.ok()
                .contentType(MediaType.IMAGE_PNG)
                .cacheControl(CacheControl.maxAge(Duration.ofHours(6)).cachePublic())
                .body(png);
    }
}
