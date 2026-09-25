package com.tecsys.gatewayplanner.model;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.JoinTable;
import jakarta.persistence.ManyToMany;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Um cenário de planejamento já executado (aba "Comparar Cenários" do app).
 * O algoritmo de otimização em si continua rodando no Flutter — aqui só
 * guardamos o resultado, para que o histórico sobreviva entre sessões.
 *
 * A relação @ManyToMany com CandidateSite representa "quais gateways foram
 * escolhidos nesse cenário". O Hibernate cria a tabela de junção
 * "scenario_gateway" automaticamente a partir do @JoinTable abaixo.
 */
@Entity
@Table(name = "scenario")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class Scenario {

    @Id
    private String id;

    private String label;

    private LocalDateTime executedAt;

    private String distribuidora;

    // --- Parâmetros usados nesta execução ---
    private Double rangeKm;
    private Double transmissionPower;
    private Double minCoverageTarget;
    private Integer maxGateways;

    // --- Resultado ---
    private Integer totalAssets;
    private Integer coveredAssets;
    private Long processingTimeMs;

    @ManyToMany
    @JoinTable(
            name = "scenario_gateway",
            joinColumns = @JoinColumn(name = "scenario_id"),
            inverseJoinColumns = @JoinColumn(name = "candidate_site_id")
    )
    private List<CandidateSite> chosenGateways = new ArrayList<>();
}
