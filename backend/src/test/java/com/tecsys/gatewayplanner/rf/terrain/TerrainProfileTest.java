package com.tecsys.gatewayplanner.rf.terrain;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TerrainProfileTest {

    @Test
    void morroNoMeioBloqueiaOEnlace() {
        TerrainProvider hill = (lat, lon) -> {
            double d = Math.hypot(lat + 23.0, lon + 46.0);
            return 700 + 120 * Math.exp(-d * d / (2 * 0.004 * 0.004));
        };
        TerrainProfile.Result r = TerrainProfile.compute(hill, -23.0, -46.02, 6, -23.0, -45.98, 5, 915, 80);
        assertTrue(r.hasData());
        assertTrue(r.blocked());
        assertTrue(r.minClearanceM() < 0);
    }

    @Test
    void terrenoPlanoNaoBloqueia() {
        TerrainProvider flat = (lat, lon) -> 700.0;
        TerrainProfile.Result r = TerrainProfile.compute(flat, -23.0, -46.02, 6, -23.0, -45.98, 5, 915, 80);
        assertFalse(r.blocked());
    }

    @Test
    void semDadoDeRelevoNaoQuebra() {
        TerrainProvider none = (lat, lon) -> Double.NaN;
        TerrainProfile.Result r = TerrainProfile.compute(none, -23, -46, 6, -23, -45.9, 5, 915, 50);
        assertFalse(r.hasData());
    }

    @Test
    void regiaoPintaSoPertoDosPontos() {
        RegionMask m = RegionMask.of(java.util.List.of(new double[]{-23.0, -46.0}), 5);
        assertEquals(1, m.size());
        // tile z=10 que contém o ponto: o recorte intersecta o tile; um tile distante, não
        double n = 1 << 10;
        int tx = (int) Math.floor((-46.0 + 180) / 360 * n);
        double lr = Math.toRadians(-23.0);
        int ty = (int) Math.floor((1 - Math.log(Math.tan(lr) + 1 / Math.cos(lr)) / Math.PI) / 2 * n);
        assertTrue(m.tileShape(10, tx, ty).intersects(0, 0, 256, 256));
        assertFalse(m.tileShape(10, tx + 8, ty).intersects(0, 0, 256, 256));
    }
}
