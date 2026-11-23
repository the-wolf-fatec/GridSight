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

    // GET /api/distribuidoras/centros -> {"Enel Ce": [-4.1, -38.9], ...}
    // Centro dos ativos de cada distribuidora: o app descobre por ele em que região do país ela atua.
    @GetMapping("/centros")
    public java.util.Map<String, double[]> centros() {
        java.util.Map<String, double[]> out = new java.util.LinkedHashMap<>();
        for (Object[] r : candidateSiteService.findCentros()) put(out, r);
        for (Object[] r : assetService.findCentros()) put(out, r); // ativos valem mais que candidatos
        return out;
    }

    private static void put(java.util.Map<String, double[]> out, Object[] r) {
        if (r[0] == null || r[1] == null || r[2] == null) return;
        out.put(r[0].toString(), new double[]{((Number) r[1]).doubleValue(), ((Number) r[2]).doubleValue()});
    }
}