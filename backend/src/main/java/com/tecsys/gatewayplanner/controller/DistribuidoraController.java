package com.tecsys.gatewayplanner.controller;

import com.tecsys.gatewayplanner.service.AssetService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/distribuidoras")
public class DistribuidoraController {

    private final AssetService assetService;

    public DistribuidoraController(AssetService assetService) {
        this.assetService = assetService;
    }

    // GET /api/distribuidoras -> ["EDP São Paulo", "CPFL Paulista", ...]
    @GetMapping
    public List<String> list() {
        return assetService.findDistribuidoras();
    }
}
