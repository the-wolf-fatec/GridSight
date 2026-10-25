package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.planning.PlanRequest;
import com.tecsys.gatewayplanner.planning.PlanResponse;
import com.tecsys.gatewayplanner.service.PlanningService;
import com.tecsys.gatewayplanner.service.TerrainService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Planejamento de gateways com relevo.
 *
 *   POST /api/planning/run             otimiza (ou avalia gateways manuais) e devolve cobertura, relevo e ligações
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
