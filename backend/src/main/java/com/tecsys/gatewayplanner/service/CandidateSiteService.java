package com.tecsys.gatewayplanner.service;

import com.tecsys.gatewayplanner.model.CandidateSite;
import com.tecsys.gatewayplanner.repository.CandidateSiteRepository;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class CandidateSiteService {

    private final CandidateSiteRepository repository;

    public CandidateSiteService(CandidateSiteRepository repository) {
        this.repository = repository;
    }

    public List<CandidateSite> findByDistribuidora(String distribuidora) {
        return repository.findByDistribuidora(distribuidora);
    }

    public CandidateSite save(CandidateSite site) {
        return repository.save(site);
    }

    public List<CandidateSite> findManualSites() {
        return repository.findByIdStartingWith("manual-");
    }

    // Usado pelo DistribuidoraController — algumas distribuidoras (ex.:
    // Neoenergia Elektro) ainda só têm locais candidatos importados, sem
    // nenhum ativo ainda. Sem isso, elas não apareceriam no dropdown do
    // app até ter pelo menos um Asset gravado.
    public List<String> findDistribuidoras() {
        return repository.findDistinctDistribuidoras();
    }
}