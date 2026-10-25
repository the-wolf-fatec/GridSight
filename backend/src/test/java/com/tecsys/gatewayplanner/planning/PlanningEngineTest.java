package com.tecsys.gatewayplanner.planning;

import com.tecsys.gatewayplanner.rf.Geo;
import com.tecsys.gatewayplanner.rf.terrain.TerrainProvider;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Terreno sintético: planície a 100 m com uma serra de 400 m de altura cortando
 * o caminho entre o gateway A (oeste) e o ativo X (leste). O gateway B fica do
 * lado de X da serra.
 *
 *   A (-46.0000)  ---- serra (-45.9855) ----  B (-45.9752)  X (-45.9707)
 */
class PlanningEngineTest {

    private static final double LAT = -23.0;
    private static final double RIDGE_LON = -45.9855;

    /** Planície com uma serra de ~150 m de largura e +400 m. */
    private static final TerrainProvider RIDGE = (lat, lon) -> Math.abs(lon - RIDGE_LON) < 0.00075 ? 500 : 100;

    private static PlanRequest.Site site(String id, double lon) {
        PlanRequest.Site s = new PlanRequest.Site();
        s.id = id;
        s.name = id;
        s.type = "teste";
        s.lat = LAT;
        s.lon = lon;
        return s;
    }

    private static PlanRequest request(boolean useTerrain, PlanRequest.Site... candidates) {
        PlanRequest.Group g = new PlanRequest.Group();
        g.name = "teste";
        g.assets = List.of(site("X", -45.9707));
        g.candidates = List.of(candidates);
        PlanRequest r = new PlanRequest();
        r.rangeKm = 5;
        r.txPowerDbm = 20;
        r.maxGateways = 3;
        r.useTerrain = useTerrain;
        r.groups = List.of(g);
        return r;
    }

    @Test
    void semRelevoOGatewayDoOutroLadoDaSerraCobre() {
        PlanResponse p = PlanningEngine.run(request(false, site("A", -46.0)), RIDGE, 5);
        assertEquals(1, p.coveredAssets());
        assertFalse(p.terrainUsed());
    }

    @Test
    void comRelevoASerraBloqueiaEOAtivoApareceComoPerdido() {
        PlanResponse p = PlanningEngine.run(request(true, site("A", -46.0)), RIDGE, 5);
        assertTrue(p.terrainUsed());
        assertEquals(0, p.coveredAssets());
        assertEquals(List.of("X"), p.lostToTerrainAssetIds()); // o relevo é o motivo
        assertEquals(1, p.withoutTerrain().coveredByDistance());
        assertEquals(0, p.withoutTerrain().coveredWithTerrain());
    }

    @Test
    void comRelevoOAlgoritmoEscolheOGatewayQueEnxerga() {
        PlanResponse p = PlanningEngine.run(request(true, site("A", -46.0), site("B", -45.9752)), RIDGE, 5);
        assertEquals(List.of("B"), p.chosenGatewayIds());
        assertEquals(1, p.coveredAssets());
        assertEquals("B", p.links().get(0).gatewayId());
        assertTrue(p.links().get(0).rxDbm() < 0);
    }

    @Test
    void semArquivosDeRelevoCaiParaDistanciaEAvisa() {
        TerrainProvider none = (lat, lon) -> Double.NaN;
        PlanResponse p = PlanningEngine.run(request(true, site("A", -46.0)), none, 5);
        assertFalse(p.terrainUsed());
        assertFalse(p.warnings().isEmpty());
        assertEquals(1, p.coveredAssets());
    }

    @Test
    void areaDeCoberturaECortadaPelaSerra() {
        PlanRequest r = request(true, site("A", -46.0));
        r.groups.get(0).manualGatewayIds = List.of("A"); // avalia o gateway A (a otimização não escolheria um gateway sem cobertura)
        PlanResponse p = PlanningEngine.run(r, RIDGE, 5);
        List<double[]> pts = p.footprints().get(0).points();
        double east = Geo.distanceKm(LAT, -46.0, pts.get(9)[0], pts.get(9)[1]);   // 90° = leste, na direção da serra
        double west = Geo.distanceKm(LAT, -46.0, pts.get(27)[0], pts.get(27)[1]); // 270° = oeste, planície
        assertTrue(east < 2.0, "a serra a ~1,5 km deve cortar a área para leste: " + east);
        assertTrue(west > 4.5, "para oeste o sinal chega até o teto de 5 km: " + west);
    }

    private static boolean inQuad(List<double[]> q, double lat, double lon) {
        boolean in = false;
        for (int i = 0, j = q.size() - 1; i < q.size(); j = i++) {
            double[] a = q.get(i), b = q.get(j);
            if ((a[0] > lat) != (b[0] > lat) && lon < (b[1] - a[1]) * (lat - a[0]) / (b[0] - a[0]) + a[1]) in = !in;
        }
        return in;
    }

    @Test
    void areaSemSinalSoNaRedeENuncaSobreAtivoCoberto() {
        PlanRequest r = request(true, site("A", -46.0));
        r.groups.get(0).manualGatewayIds = List.of("A");
        PlanResponse p = PlanningEngine.run(r, RIDGE, 5);
        List<List<double[]>> sh = p.footprints().get(0).shadows();
        assertFalse(sh.isEmpty(), "atrás da serra, perto do ativo X, deve haver área sem sinal");
        for (List<double[]> q : sh) {
            double cLat = q.stream().mapToDouble(x -> x[0]).average().orElse(0);
            double cLon = q.stream().mapToDouble(x -> x[1]).average().orElse(0);
            // a até ~6 km (+ meia célula) do único ativo
            assertTrue(Geo.distanceKm(cLat, cLon, LAT, -45.9707) <= 7.5, "magenta longe da rede");
        }
        // com o gateway B (que enxerga X) o ativo está coberto e nenhum pedaço magenta o contém
        PlanRequest r2 = request(true, site("A", -46.0), site("B", -45.9752));
        PlanResponse p2 = PlanningEngine.run(r2, RIDGE, 5);
        assertEquals(1, p2.coveredAssets());
        for (PlanResponse.Footprint f : p2.footprints())
            for (List<double[]> q : f.shadows()) assertFalse(inQuad(q, LAT, -45.9707), "magenta sobre ativo coberto");
    }

    @Test
    void avaliacaoManualNaoOtimiza() {
        PlanRequest r = request(true, site("A", -46.0), site("B", -45.9752));
        r.groups.get(0).manualGatewayIds = List.of("A");
        PlanResponse p = PlanningEngine.run(r, RIDGE, 5);
        assertEquals(List.of("A"), p.chosenGatewayIds());
        assertEquals(0, p.coveredAssets());
    }
}
