package com.tecsys.gatewayplanner.service;

import com.tecsys.gatewayplanner.planning.PlanRequest;
import com.tecsys.gatewayplanner.planning.PlanResponse;
import com.tecsys.gatewayplanner.planning.PlanningEngine;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class PlanningService {

    private final TerrainService terrainService;
    private final double fadeMarginDb;

    public PlanningService(TerrainService terrainService,
                           @Value("${gridsight.rf.fade-margin-db:0}") double fadeMarginDb) {
        this.terrainService = terrainService;
        this.fadeMarginDb = fadeMarginDb;
    }

    public java.util.List<PlanResponse.PeakSuggestion> suggestPeaks(PlanRequest request) {
        return PlanningEngine.suggestPeaks(request, terrainService.provider(), fadeMarginDb);
    }

    public PlanResponse run(PlanRequest request) {
        return PlanningEngine.run(request, terrainService.provider(), fadeMarginDb);
    }
}
