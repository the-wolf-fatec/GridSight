package com.tecsys.gatewayplanner.controller;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * Proxy para os tiles do OpenStreetMap.
 *
 * Por quê: no Flutter Web, o navegador é quem controla o header
 * "User-Agent" — o app nunca consegue sobrescrevê-lo de verdade. Desde
 * meados de 2026, o servidor oficial do OSM (tile.openstreetmap.org)
 * passou a bloquear (403 Forbidden) tráfego com User-Agent genérico/não
 * identificado, o que derruba o mapa em qualquer app Flutter Web que
 * aponte direto pra lá.
 *
 * Esta chamada sai do BACKEND (Java), não do navegador — então dá pra
 * mandar um User-Agent real, identificando a aplicação, exatamente como a
 * política de uso do OSM pede. O Flutter passa a pedir os tiles pra cá
 * (mesma origem do resto da API, sem CORS extra) em vez de ir direto no
 * OSM, e a gente repassa a imagem.
 */
@RestController
public class TileProxyController {

    // Troque pelo nome/contato reais do seu projeto — é o que a política
    // de uso do OSM pede: https://operations.osmfoundation.org/policies/tiles/
    private static final String USER_AGENT =
            "GridSight/1.0 (desafio Tecsys - Fatec SJC; contato: seu-email@exemplo.com)";

    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .build();

    @GetMapping("/api/tiles/{z}/{x}/{y}.png")
    public ResponseEntity<byte[]> tile(
            @PathVariable int z,
            @PathVariable int x,
            @PathVariable int y
    ) {
        String url = String.format("https://tile.openstreetmap.org/%d/%d/%d.png", z, x, y);

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .header("User-Agent", USER_AGENT)
                .timeout(Duration.ofSeconds(8))
                .GET()
                .build();

        try {
            HttpResponse<byte[]> response = httpClient.send(request, HttpResponse.BodyHandlers.ofByteArray());

            if (response.statusCode() != 200) {
                return ResponseEntity.status(response.statusCode()).build();
            }

            return ResponseEntity.ok()
                    .contentType(MediaType.IMAGE_PNG)
                    // Cache no navegador por 1 dia — tiles do OSM não mudam
                    // de um minuto pro outro, e isso poupa o backend de
                    // repetir a mesma chamada toda hora.
                    .header(HttpHeaders.CACHE_CONTROL, "public, max-age=86400")
                    .body(response.body());
        } catch (IOException | InterruptedException e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).build();
        }
    }
}
