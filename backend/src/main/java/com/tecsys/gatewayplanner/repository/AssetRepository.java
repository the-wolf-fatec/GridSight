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

    // Centro (média de lat/lon, só pontos dentro do Brasil) dos ativos de cada distribuidora: define a região dela.
    @org.springframework.data.jpa.repository.Query("SELECT a.distribuidora, AVG(a.latitude), AVG(a.longitude) FROM Asset a "
            + "WHERE a.latitude BETWEEN -35 AND 6 AND a.longitude BETWEEN -75 AND -33 GROUP BY a.distribuidora")
    List<Object[]> findCentros();

    // Ladrilhos (1° x 1°) onde há pontos: usado para baixar o relevo em segundo plano ao subir o backend.
    @org.springframework.data.jpa.repository.Query("SELECT DISTINCT FLOOR(a.latitude), FLOOR(a.longitude) FROM Asset a "
            + "WHERE a.latitude BETWEEN -35 AND 6 AND a.longitude BETWEEN -75 AND -33")
    List<Object[]> findTiles();
}
