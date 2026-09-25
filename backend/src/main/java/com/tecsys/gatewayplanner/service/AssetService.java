package com.tecsys.gatewayplanner.service;

import com.tecsys.gatewayplanner.model.Asset;
import com.tecsys.gatewayplanner.repository.AssetRepository;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class AssetService {

    private final AssetRepository repository;

    public AssetService(AssetRepository repository) {
        this.repository = repository;
    }

    public List<Asset> findByDistribuidora(String distribuidora) {
        return repository.findByDistribuidora(distribuidora);
    }

    public List<String> findDistribuidoras() {
        return repository.findDistinctDistribuidoras();
    }

    public List<Asset> findManualAssets() {
        return repository.findByIdStartingWith("manual-");
    }

    public Asset save(Asset asset) {
        return repository.save(asset);
    }
}
