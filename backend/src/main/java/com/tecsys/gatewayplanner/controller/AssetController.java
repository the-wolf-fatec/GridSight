package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.model.Asset;
import com.tecsys.gatewayplanner.service.AssetService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/assets")
public class AssetController {

    private final AssetService assetService;

    public AssetController(AssetService assetService) {
        this.assetService = assetService;
    }

    // GET /api/assets?distribuidora=EDP São Paulo
    @GetMapping
    public List<Asset> list(@RequestParam String distribuidora) {
        return assetService.findByDistribuidora(distribuidora);
    }

    // GET /api/assets/manual — só os ativos criados pelo modal "Novo ativo
    // de rede" (de qualquer distribuidora). Usado pelo Flutter para
    // restaurar apenas esses ao iniciar/F5, sem reimportar o resto da BDGD.
    @GetMapping("/manual")
    public List<Asset> listManual() {
        return assetService.findManualAssets();
    }

    // POST /api/assets — cria um ativo cadastrado manualmente pelo modal
    // "Novo ativo de rede" no Flutter. O id é gerado no backend (não confia
    // no que o cliente mandar) para não colidir com ids de outra origem.
    @PostMapping
    public ResponseEntity<Asset> create(@RequestBody Asset asset) {
        asset.setId("manual-" + java.util.UUID.randomUUID());
        Asset saved = assetService.save(asset);
        return ResponseEntity.ok(saved);
    }
}
