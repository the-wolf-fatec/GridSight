package com.tecsys.gatewayplanner.service;

import com.tecsys.gatewayplanner.planning.PlanRequest;
import com.tecsys.gatewayplanner.planning.PlanResponse;
import com.tecsys.gatewayplanner.planning.PlanningEngine;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class PlanningService {

    private final TerrainService terrainService;
    private final ClutterService clutterService;
    private final double fadeMarginDb;

    public PlanningService(TerrainService terrainService, ClutterService clutterService,
                           @Value("${gridsight.rf.fade-margin-db:0}") double fadeMarginDb) {
        this.terrainService = terrainService;
        this.clutterService = clutterService;
        this.fadeMarginDb = fadeMarginDb;
    }

    public java.util.List<PlanResponse.PeakSuggestion> suggestPeaks(PlanRequest request) {
        java.util.List<String> ignored = new java.util.ArrayList<>();
        boolean clutter = request.useTerrain && request.useClutter && clutterService.prepare(request, ignored);
        return PlanningEngine.suggestPeaks(request, terrainService.provider(), clutter ? clutterService : null, fadeMarginDb);
    }

    public PlanResponse run(PlanRequest request) {
        java.util.List<String> warnings = new java.util.ArrayList<>();
        boolean clutter = request.useTerrain && request.useClutter && clutterService.prepare(request, warnings);
        if (request.useTerrain && request.useClutter && !clutter) {
            warnings.add("Árvores e prédios não puderam ser carregados; o cálculo usou só o relevo.");
        }
        return PlanningEngine.run(request, terrainService.provider(), clutter ? clutterService : null, warnings, fadeMarginDb);
    }
}
