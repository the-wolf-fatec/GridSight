package com.tecsys.gatewayplanner.controller;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

// Faz o papel de intermediário entre o app Flutter e o Nominatim
// (OpenStreetMap), igual o TileProxyController já fazia pros tiles do
// mapa. O app NÃO consegue chamar o Nominatim direto (CORS no Flutter Web,
// e algumas políticas de rede no Android bloqueiam também) — então o
// backend busca por ele e devolve o resultado pronto.
@RestController
@RequestMapping("/api/geocode")
public class GeocodeProxyController {

    private final RestTemplate restTemplate = new RestTemplate();

    // Garante no MÍNIMO 1,1s entre cada pedido de verdade pro Nominatim,
    // não importa de quantos lugares do app os pedidos vierem — é a regra
    // de uso deles (1 req/s). Sem isso, qualquer digitação rápida ou duas
    // telas buscando ao mesmo tempo pode estourar o limite e tomar bloqueio
    // (como já aconteceu). "synchronized" garante que só 1 requisição por
    // vez passa por aqui, mesmo com vários usuários/telas simultâneos.
    private static final long MIN_INTERVAL_MS = 1100;
    private long lastRequestAt = 0;

    private synchronized void respectRateLimit() throws InterruptedException {
        long now = System.currentTimeMillis();
        long wait = MIN_INTERVAL_MS - (now - lastRequestAt);
        if (wait > 0) Thread.sleep(wait);
        lastRequestAt = System.currentTimeMillis();
    }

    @GetMapping
    public ResponseEntity<String> search(@RequestParam("q") String query) {
        String encoded = URLEncoder.encode(query, StandardCharsets.UTF_8);
        URI uri = URI.create("https://nominatim.openstreetmap.org/search?format=json&limit=5&countrycodes=br&q=" + encoded);
        return proxy(uri);
    }

    // GET /api/geocode/reverse?lat=...&lon=... -> descobre cidade/bairro a
    // partir de uma coordenada. Usado quando toca num ativo/candidato no
    // mapa pra mostrar "onde" ele está, sem precisar guardar cidade/bairro
    // como campo próprio no banco.
    @GetMapping("/reverse")
    public ResponseEntity<String> reverse(@RequestParam("lat") double lat, @RequestParam("lon") double lon) {
        URI uri = URI.create("https://nominatim.openstreetmap.org/reverse?format=json&lat=" + lat + "&lon=" + lon + "&zoom=16&addressdetails=1");
        return proxy(uri);
    }

    private ResponseEntity<String> proxy(URI uri) {
        try {
            respectRateLimit();

            HttpHeaders headers = new HttpHeaders();
            // Nominatim exige um User-Agent identificável — sem isso, recusa a
            // requisição (mesmo problema que tivemos com os tiles).
            headers.set("User-Agent", "GridSight-Tecsys-FatecSJC/1.0 (academic project)");
            headers.set("Accept-Language", "pt-BR");

            org.springframework.http.HttpEntity<Void> entity = new org.springframework.http.HttpEntity<>(headers);
            ResponseEntity<String> response = restTemplate.exchange(uri, HttpMethod.GET, entity, String.class);

            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_TYPE, "application/json")
                    .body(response.getBody());
        } catch (org.springframework.web.client.HttpClientErrorException.TooManyRequests e) {
            // Mesmo respeitando 1,1s, o Nominatim pode manter um bloqueio
            // temporário de uma rajada de testes anterior. Devolve lista
            // vazia em vez de erro 500 — o app só mostra "sem resultado",
            // sem travar nada.
            return ResponseEntity.ok().header(HttpHeaders.CONTENT_TYPE, "application/json").body("[]");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ResponseEntity.ok().header(HttpHeaders.CONTENT_TYPE, "application/json").body("[]");
        }
    }
}