package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.service.AssetService;
import com.tecsys.gatewayplanner.service.CandidateSiteService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

@RestController
@RequestMapping("/api/distribuidoras")
public class DistribuidoraController {

    private final AssetService assetService;
    private final CandidateSiteService candidateSiteService;

    public DistribuidoraController(AssetService assetService, CandidateSiteService candidateSiteService) {
        this.assetService = assetService;
        this.candidateSiteService = candidateSiteService;
    }

    // GET /api/distribuidoras -> ["EDP São Paulo", "CPFL Paulista", ...]
    //
    // Junta as distribuidoras que têm Ativos COM as que têm Locais
    // Candidatos — algumas (ex.: Neoenergia Elektro, enquanto só tem
    // subestação/poste importado, sem ativo ainda) só apareceriam numa das
    // duas listas se não fizéssemos essa união. LinkedHashSet remove
    // duplicata mantendo a ordem de quem apareceu primeiro.
    @GetMapping
    public List<String> list() {
        Set<String> todas = new LinkedHashSet<>(assetService.findDistribuidoras());
        todas.addAll(candidateSiteService.findDistribuidoras());
        todas.removeIf(d -> d == null || d.isBlank()); // registros antigos sem distribuidora não podem derrubar a lista
        return List.copyOf(todas);
    }
}