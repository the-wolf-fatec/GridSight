package com.tecsys.gatewayplanner.planning;

import com.tecsys.gatewayplanner.rf.terrain.TerrainProvider;
import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Redundância: 9 ativos em linha e 2 gateways que se sobrepõem no meio.
 * Os ativos das pontas só têm um gateway; os do meio têm os dois.
 */
class RedundancyTest {

    private static PlanRequest.Site site(String id, double lon) {
        PlanRequest.Site s = new PlanRequest.Site();
        s.id = id;
        s.name = id;
        s.type = "teste";
        s.lat = -23.0;
        s.lon = lon;
        return s;
    }

    @Test
    void ativosSoAtendidosPorUmGatewayFicamNasDependencias() {
        TerrainProvider flat = (lat, lon) -> 700.0;
        PlanRequest req = new PlanRequest();
        req.rangeKm = 1.2;
        req.useTerrain = false;
        req.maxGateways = 2;
        PlanRequest.Group g = new PlanRequest.Group();
        g.name = "G";
        for (int i = 0; i < 9; i++) g.assets.add(site("a" + i, -46.0 + i * 0.003));
        g.candidates.add(site("c0", -46.0 + 0.003 * 1.5));
        g.candidates.add(site("c1", -46.0 + 0.003 * 6.5));
        req.groups.add(g);

        PlanResponse resp = PlanningEngine.run(req, flat, 0);

        assertEquals(9, resp.coveredAssets());
        assertEquals(2, resp.dependencies().size());
        Set<String> exclusivos = new HashSet<>();
        for (PlanResponse.Dependency d : resp.dependencies()) exclusivos.addAll(d.exclusiveAssetIds());
        // exclusivos + sobrepostos = cobertos
        assertEquals(resp.coveredAssets(), exclusivos.size() + resp.overlappedAssets());
        assertTrue(exclusivos.contains("a0"));
        assertTrue(exclusivos.contains("a8"));
    }
}
