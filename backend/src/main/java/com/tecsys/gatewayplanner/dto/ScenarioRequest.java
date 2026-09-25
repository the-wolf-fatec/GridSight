package com.tecsys.gatewayplanner.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.List;

/**
 * Corpo esperado em POST /api/scenarios.
 * O Flutter já roda o algoritmo de otimização localmente; aqui só
 * recebemos o resultado pronto para persistir.
 */
public class ScenarioRequest {

    @NotBlank
    private String label;

    @NotBlank
    private String distribuidora;

    @NotNull
    private Double rangeKm;

    @NotNull
    private Double transmissionPower;

    @NotNull
    private Double minCoverageTarget;

    @NotNull
    private Integer maxGateways;

    @NotNull
    private Integer totalAssets;

    @NotNull
    private Integer coveredAssets;

    @NotNull
    private Long processingTimeMs;

    /** IDs dos CandidateSite escolhidos como gateway (precisam já existir no banco). */
    @NotNull
    private List<String> chosenGatewayIds;

    // --- getters e setters ---

    public String getLabel() { return label; }
    public void setLabel(String label) { this.label = label; }

    public String getDistribuidora() { return distribuidora; }
    public void setDistribuidora(String distribuidora) { this.distribuidora = distribuidora; }

    public Double getRangeKm() { return rangeKm; }
    public void setRangeKm(Double rangeKm) { this.rangeKm = rangeKm; }

    public Double getTransmissionPower() { return transmissionPower; }
    public void setTransmissionPower(Double transmissionPower) { this.transmissionPower = transmissionPower; }

    public Double getMinCoverageTarget() { return minCoverageTarget; }
    public void setMinCoverageTarget(Double minCoverageTarget) { this.minCoverageTarget = minCoverageTarget; }

    public Integer getMaxGateways() { return maxGateways; }
    public void setMaxGateways(Integer maxGateways) { this.maxGateways = maxGateways; }

    public Integer getTotalAssets() { return totalAssets; }
    public void setTotalAssets(Integer totalAssets) { this.totalAssets = totalAssets; }

    public Integer getCoveredAssets() { return coveredAssets; }
    public void setCoveredAssets(Integer coveredAssets) { this.coveredAssets = coveredAssets; }

    public Long getProcessingTimeMs() { return processingTimeMs; }
    public void setProcessingTimeMs(Long processingTimeMs) { this.processingTimeMs = processingTimeMs; }

    public List<String> getChosenGatewayIds() { return chosenGatewayIds; }
    public void setChosenGatewayIds(List<String> chosenGatewayIds) { this.chosenGatewayIds = chosenGatewayIds; }
}
