package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.planning.PlanRequest;
import com.tecsys.gatewayplanner.planning.PlanResponse;
import com.tecsys.gatewayplanner.rf.terrain.TerrainProfile;
import com.tecsys.gatewayplanner.service.PlanningService;
import com.tecsys.gatewayplanner.service.TerrainService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Planejamento de gateways com relevo.
 *
 *   POST /api/planning/run             otimiza (ou avalia gateways manuais) e devolve cobertura, relevo e ligações
 *   GET  /api/planning/profile         perfil de elevação de um enlace (chão, visada, Fresnel)
 *   GET  /api/planning/terrain-status  mostra quais arquivos .hgt o backend encontrou
 */
@RestController
@RequestMapping("/api/planning")
public class PlanningController {

    private final PlanningService planningService;
    private final TerrainService terrainService;

    public PlanningController(PlanningService planningService, TerrainService terrainService) {
        this.planningService = planningService;
        this.terrainService = terrainService;
    }

    @PostMapping("/run")
    public PlanResponse run(@RequestBody PlanRequest request) {
        return planningService.run(request);
    }

    /** Pontos altos onde um gateway novo recuperaria ativos hoje sem sinal por causa do relevo. */
    @PostMapping("/suggest-peaks")
    public java.util.List<PlanResponse.PeakSuggestion> suggestPeaks(@RequestBody PlanRequest request) {
        return planningService.suggestPeaks(request);
    }

    /**
     * Perfil de elevação entre um gateway e um ativo: chão, linha de visada e Fresnel.
     * GET /api/planning/profile?lat1=..&lon1=..&lat2=..&lon2=..&h1=6&h2=5&freq=915&n=120
     */
    @GetMapping("/profile")
    public TerrainProfile.Result profile(@RequestParam double lat1, @RequestParam double lon1,
                                         @RequestParam double lat2, @RequestParam double lon2,
                                         @RequestParam(defaultValue = "6") double h1,
                                         @RequestParam(defaultValue = "5") double h2,
                                         @RequestParam(defaultValue = "915") double freq,
                                         @RequestParam(defaultValue = "120") int n) {
        if (Math.abs(lat1) > 90 || Math.abs(lat2) > 90 || Math.abs(lon1) > 180 || Math.abs(lon2) > 180) {
            throw new IllegalArgumentException("Coordenadas inválidas.");
        }
        return TerrainProfile.compute(terrainService.provider(), lat1, lon1, Math.max(0, h1), lat2, lon2, Math.max(0, h2),
                Math.min(6000, Math.max(30, freq)), n);
    }

    @GetMapping("/terrain-status")
    public Map<String, Object> terrainStatus() {
        return terrainService.status();
    }

    @ExceptionHandler(IllegalArgumentException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Map<String, String> badRequest(IllegalArgumentException e) {
        return Map.of("error", e.getMessage() == null ? "Pedido inválido" : e.getMessage());
    }
}
