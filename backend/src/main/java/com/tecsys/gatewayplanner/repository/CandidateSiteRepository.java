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

    // Centro dos locais candidatos de cada distribuidora (para as que ainda não têm ativos).
    @Query("SELECT c.distribuidora, AVG(c.latitude), AVG(c.longitude) FROM CandidateSite c "
            + "WHERE c.latitude BETWEEN -35 AND 6 AND c.longitude BETWEEN -75 AND -33 GROUP BY c.distribuidora")
    List<Object[]> findCentros();
}