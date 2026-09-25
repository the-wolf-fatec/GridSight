package com.tecsys.gatewayplanner.repository;

import com.tecsys.gatewayplanner.model.CandidateSite;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface CandidateSiteRepository extends JpaRepository<CandidateSite, String> {

    List<CandidateSite> findByDistribuidora(String distribuidora);

    // Usado pelo endpoint GET /api/candidate-sites/manual
    List<CandidateSite> findByIdStartingWith(String prefix);
}
