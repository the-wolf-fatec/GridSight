package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.rf.clutter.ClutterTileRenderer;
import com.tecsys.gatewayplanner.service.ClutterService;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.time.Duration;

/**
 * Tiles de ÁRVORES e PRÉDIOS para sobrepor ao mapa (verde = mata, laranja = prédio), dos mesmos
 * dados usados no cálculo. Visíveis a partir do zoom 12. Na primeira vez que uma região é mostrada
 * o backend baixa os dados do OpenStreetMap (alguns segundos); depois vêm do cache em disco.
 *
 * GET /api/clutter/tiles/{z}/{x}/{y}.png
 */
@RestController
public class ClutterTileController {

    private final ClutterService clutter;

    public ClutterTileController(ClutterService clutter) {
        this.clutter = clutter;
    }

    @GetMapping("/api/clutter/tiles/{z}/{x}/{y}.png")
    public ResponseEntity<byte[]> tile(@PathVariable int z, @PathVariable int x, @PathVariable int y) throws IOException {
        if (z >= ClutterTileRenderer.MIN_ZOOM && z <= 22 && x >= 0 && y >= 0 && x < (1 << z) && y < (1 << z)) {
            int n = 1 << z;
            double west = x * 360.0 / n - 180, east = (x + 1) * 360.0 / n - 180;
            double north = lat(y, n), south = lat(y + 1, n);
            clutter.ensureArea(south, west, north, east);
        }
        byte[] png = ClutterTileRenderer.png(clutter, z, x, y);
        return ResponseEntity.ok()
                .contentType(MediaType.IMAGE_PNG)
                .cacheControl(CacheControl.maxAge(Duration.ofMinutes(5)).cachePublic())
                .body(png);
    }

    private static double lat(int ty, int n) {
        return Math.toDegrees(Math.atan(Math.sinh(Math.PI * (1 - 2.0 * ty / n))));
    }
}
