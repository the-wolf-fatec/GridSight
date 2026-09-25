package com.tecsys.gatewayplanner.dto;

import com.tecsys.gatewayplanner.model.CandidateSite;
import com.tecsys.gatewayplanner.model.Scenario;

import java.time.LocalDateTime;
import java.util.List;

/**
 * Formato devolvido por GET/POST /api/scenarios — já no shape que o
 * ScenarioResult do Flutter espera (ver lib/models/scenario_result.dart).
 */
public class ScenarioResponse {

    private String id;
    private String label;
    private LocalDateTime executedAt;
    private String distribuidora;

    private Double rangeKm;
    private Double transmissionPower;
    private Double minCoverageTarget;
    private Integer maxGateways;

    private Integer totalAssets;
    private Integer coveredAssets;
    private Long processingTimeMs;

    private List<CandidateSite> chosenGateways;

    public static ScenarioResponse fromEntity(Scenario s) {
        ScenarioResponse dto = new ScenarioResponse();
        dto.id = s.getId();
        dto.label = s.getLabel();
        dto.executedAt = s.getExecutedAt();
        dto.distribuidora = s.getDistribuidora();
        dto.rangeKm = s.getRangeKm();
        dto.transmissionPower = s.getTransmissionPower();
        dto.minCoverageTarget = s.getMinCoverageTarget();
        dto.maxGateways = s.getMaxGateways();
        dto.totalAssets = s.getTotalAssets();
        dto.coveredAssets = s.getCoveredAssets();
        dto.processingTimeMs = s.getProcessingTimeMs();
        dto.chosenGateways = s.getChosenGateways();
        return dto;
    }

    // --- getters (sem setters: este DTO é só de saída) ---

    public String getId() { return id; }
    public String getLabel() { return label; }
    public LocalDateTime getExecutedAt() { return executedAt; }
    public String getDistribuidora() { return distribuidora; }
    public Double getRangeKm() { return rangeKm; }
    public Double getTransmissionPower() { return transmissionPower; }
    public Double getMinCoverageTarget() { return minCoverageTarget; }
    public Integer getMaxGateways() { return maxGateways; }
    public Integer getTotalAssets() { return totalAssets; }
    public Integer getCoveredAssets() { return coveredAssets; }
    public Long getProcessingTimeMs() { return processingTimeMs; }
    public List<CandidateSite> getChosenGateways() { return chosenGateways; }
}
