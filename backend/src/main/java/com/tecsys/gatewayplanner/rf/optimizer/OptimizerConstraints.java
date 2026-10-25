package com.tecsys.gatewayplanner.rf.optimizer;

import java.util.HashSet;
import java.util.Set;

/** Restrições operacionais da análise. */
public class OptimizerConstraints {
    /** Limite de quantidade de gateways. */
    public int maxGateways = 12;
    /** Meta de cobertura (0..1); a busca para quando atinge. */
    public double minCoverageTarget = 1.0;
    /** Locais proibidos (ex.: sem energia, área não permitida). */
    public Set<String> forbiddenCandidateIds = new HashSet<>();
    /** Locais que obrigatoriamente entram na solução. */
    public Set<String> requiredCandidateIds = new HashSet<>();
}
