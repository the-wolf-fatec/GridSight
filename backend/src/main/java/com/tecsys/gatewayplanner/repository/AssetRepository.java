package com.tecsys.gatewayplanner.repository;

import com.tecsys.gatewayplanner.model.Asset;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AssetRepository extends JpaRepository<Asset, String> {

    List<Asset> findByDistribuidora(String distribuidora);

    // Usado pelo endpoint GET /api/assets/manual — ativos criados pelo
    // modal "Novo ativo de rede" sempre recebem id com esse prefixo
    // (ver AssetController.create), então dá pra filtrar só eles.
    List<Asset> findByIdStartingWith(String prefix);

    // Usado pelo endpoint GET /api/distribuidoras
    @org.springframework.data.jpa.repository.Query("SELECT DISTINCT a.distribuidora FROM Asset a ORDER BY a.distribuidora")
    List<String> findDistinctDistribuidoras();
}
