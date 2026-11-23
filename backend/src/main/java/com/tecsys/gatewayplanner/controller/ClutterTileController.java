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
        int pending = 0;
        if (z >= ClutterTileRenderer.MIN_ZOOM && z <= 22 && x >= 0 && y >= 0 && x < (1 << z) && y < (1 << z)) {
            int n = 1 << z;
            double west = x * 360.0 / n - 180, east = (x + 1) * 360.0 / n - 180;
            double north = lat(y, n), south = lat(y + 1, n);
            pending = clutter.ensureAreaAsync(south, west, north, east); // não espera o download
        }
        byte[] png = ClutterTileRenderer.png(clutter, z, x, y);
        // Enquanto ainda baixa, não deixa o navegador guardar o ladrilho vazio: mexer no mapa busca de novo.
        CacheControl cc = pending > 0 ? CacheControl.noStore() : CacheControl.maxAge(Duration.ofMinutes(5)).cachePublic();
        return ResponseEntity.ok().contentType(MediaType.IMAGE_PNG).cacheControl(cc).body(png);
    }

    /** GET /api/clutter/status: quantos trechos já estão prontos, quantos baixando, falhas e o último erro. */
    @GetMapping("/api/clutter/status")
    public java.util.Map<String, Object> status() {
        return clutter.status();
    }

    /** GET /api/clutter/test?lat=-23.55&lon=-46.63: baixa um trecho agora e diz se funcionou (ou o erro). */
    @GetMapping("/api/clutter/test")
    public java.util.Map<String, Object> test(@org.springframework.web.bind.annotation.RequestParam(defaultValue = "-23.55") double lat,
                                              @org.springframework.web.bind.annotation.RequestParam(defaultValue = "-46.63") double lon) {
        return clutter.test(lat, lon);
    }

    private static double lat(int ty, int n) {
        return Math.toDegrees(Math.atan(Math.sinh(Math.PI * (1 - 2.0 * ty / n))));
    }
}
