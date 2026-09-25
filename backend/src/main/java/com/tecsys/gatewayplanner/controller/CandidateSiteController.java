package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.model.CandidateSite;
import com.tecsys.gatewayplanner.service.CandidateSiteService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/candidate-sites")
public class CandidateSiteController {

    private final CandidateSiteService candidateSiteService;

    public CandidateSiteController(CandidateSiteService candidateSiteService) {
        this.candidateSiteService = candidateSiteService;
    }

    // GET /api/candidate-sites?distribuidora=EDP São Paulo
    @GetMapping
    public List<CandidateSite> list(@RequestParam String distribuidora) {
        return candidateSiteService.findByDistribuidora(distribuidora);
    }

    // GET /api/candidate-sites/manual — só os criados pelo modal "Novo
    // local candidato", de qualquer distribuidora (restauração pós-F5).
    @GetMapping("/manual")
    public List<CandidateSite> listManual() {
        return candidateSiteService.findManualSites();
    }

    // POST /api/candidate-sites — cria um local candidato manualmente.
    @PostMapping
    public ResponseEntity<CandidateSite> create(@RequestBody CandidateSite site) {
        site.setId("manual-" + java.util.UUID.randomUUID());
        CandidateSite saved = candidateSiteService.save(site);
        return ResponseEntity.ok(saved);
    }
}
