package com.tecsys.gatewayplanner.repository;

import com.tecsys.gatewayplanner.model.CandidateSite;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

public interface CandidateSiteRepository extends JpaRepository<CandidateSite, String> {

    List<CandidateSite> findByDistribuidora(String distribuidora);

    // Usado pelo endpoint GET /api/candidate-sites/manual
    List<CandidateSite> findByIdStartingWith(String prefix);

    // Usado pelo DistribuidoraController — lista as distribuidoras que têm
    // PELO MENOS UM local candidato gravado, mesmo que ainda não tenham
    // nenhum Asset (ex.: Neoenergia Elektro, enquanto só tem
    // subestação/poste importado).
    @Query("SELECT DISTINCT c.distribuidora FROM CandidateSite c")
    List<String> findDistinctDistribuidoras();
}