package com.tecsys.gatewayplanner.service;

import com.tecsys.gatewayplanner.dto.ScenarioRequest;
import com.tecsys.gatewayplanner.dto.ScenarioResponse;
import com.tecsys.gatewayplanner.model.CandidateSite;
import com.tecsys.gatewayplanner.model.Scenario;
import com.tecsys.gatewayplanner.repository.CandidateSiteRepository;
import com.tecsys.gatewayplanner.repository.ScenarioRepository;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@Service
public class ScenarioService {

    private final ScenarioRepository scenarioRepository;
    private final CandidateSiteRepository candidateSiteRepository;

    public ScenarioService(ScenarioRepository scenarioRepository, CandidateSiteRepository candidateSiteRepository) {
        this.scenarioRepository = scenarioRepository;
        this.candidateSiteRepository = candidateSiteRepository;
    }

    public List<ScenarioResponse> findAll() {
        return scenarioRepository.findAllByOrderByExecutedAtDesc()
                .stream()
                .map(ScenarioResponse::fromEntity)
                .toList();
    }

    public ScenarioResponse save(ScenarioRequest request) {
        List<CandidateSite> gateways = candidateSiteRepository.findAllById(request.getChosenGatewayIds());

        if (gateways.size() != request.getChosenGatewayIds().size()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Um ou mais IDs em chosenGatewayIds não correspondem a locais candidatos existentes."
            );
        }

        Scenario scenario = new Scenario();
        scenario.setId(UUID.randomUUID().toString());
        scenario.setLabel(request.getLabel());
        scenario.setExecutedAt(LocalDateTime.now());
        scenario.setDistribuidora(request.getDistribuidora());
        scenario.setRangeKm(request.getRangeKm());
        scenario.setTransmissionPower(request.getTransmissionPower());
        scenario.setMinCoverageTarget(request.getMinCoverageTarget());
        scenario.setMaxGateways(request.getMaxGateways());
        scenario.setTotalAssets(request.getTotalAssets());
        scenario.setCoveredAssets(request.getCoveredAssets());
        scenario.setProcessingTimeMs(request.getProcessingTimeMs());
        scenario.setChosenGateways(gateways);

        Scenario saved = scenarioRepository.save(scenario);
        return ScenarioResponse.fromEntity(saved);
    }

    public void delete(String id) {
        if (!scenarioRepository.existsById(id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Cenário não encontrado: " + id);
        }
        scenarioRepository.deleteById(id);
    }

    // Usado pelo botão "Apagar tudo" em Comparar Cenários. Precisa limpar
    // a relação @ManyToMany (tabela scenario_gateway) antes de apagar os
    // cenários — senão a constraint de FK barra o delete, igual acontecia
    // apagando na mão pelo Workbench (mesma ordem: scenario_gateway antes
    // de scenario). saveAll() força o Hibernate a gravar essa limpeza
    // antes do deleteAll() rodar.
    public void deleteAll() {
        List<Scenario> all = scenarioRepository.findAll();
        all.forEach(s -> s.getChosenGateways().clear());
        scenarioRepository.saveAll(all);
        scenarioRepository.deleteAll(all);
    }
}
