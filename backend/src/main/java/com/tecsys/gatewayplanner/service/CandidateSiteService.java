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
}
