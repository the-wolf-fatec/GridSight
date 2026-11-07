package com.tecsys.gatewayplanner.rf.clutter;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tecsys.gatewayplanner.rf.RadioParams;
import com.tecsys.gatewayplanner.rf.propagation.LinkResult;
import com.tecsys.gatewayplanner.rf.propagation.TerrainDiffractionModel;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ClutterTest {

    private static final double LAT = -23.0;

    @Test
    void leOverpassComMataEPredios() throws Exception {
        String json = """
            {"elements":[
             {"type":"way","tags":{"natural":"wood"},"geometry":[
               {"lat":-23.0,"lon":-45.99},{"lat":-23.0,"lon":-45.98},{"lat":-22.99,"lon":-45.98},{"lat":-22.99,"lon":-45.99},{"lat":-23.0,"lon":-45.99}]},
             {"type":"way","tags":{"building":"yes","building:levels":"5"},"bounds":{"minlat":-22.98,"minlon":-45.99,"maxlat":-22.9799,"maxlon":-45.9899}},
             {"type":"way","tags":{"building":"house"},"bounds":{"minlat":-22.97,"minlon":-45.99,"maxlat":-22.9699,"maxlon":-45.9899}},
             {"type":"way","tags":{"highway":"residential"},"geometry":[]}
            ]}""";
        ClutterTile t = new ClutterTile(ClutterTile.tileIndex(-23.0), ClutterTile.tileIndex(-45.99));
        OverpassClutterParser.parse(new ObjectMapper().readTree(json), t);
        assertEquals(15, t.heightAt(-22.995, -45.985), 0.01);   // dentro da mata
        assertEquals(0, t.heightAt(-22.995, -45.97), 0.01);     // fora
        assertEquals(16, t.heightAt(-22.97995, -45.98995), 0.01); // 5 andares x 3,2 m
        assertEquals(8, t.heightAt(-22.96995, -45.98995), 0.01);  // casa sem altura: padrão
        assertEquals(1, t.kindAt(-22.995, -45.985));              // mata
        assertEquals(2, t.kindAt(-22.97995, -45.98995));          // prédio
        assertEquals(0, t.kindAt(-22.995, -45.97));               // livre
    }

    @Test
    void mataNoMeioDoEnlaceReduzOSinalMasPertoDasAntenasNaoConta() {
        double[] lons = {-46.000, -45.9707};
        ClutterProvider forest = (lat, lon) -> lon > -45.9890 && lon < -45.9830 ? 15 : 0; // faixa de ~600 m no meio
        ClutterProvider nearEnds = (lat, lon) -> (lon < -45.99965 || lon > -45.97105) ? 20 : 0; // só colada nas antenas
        RadioParams p = new RadioParams();
        p.txPowerDbm = 20;
        var flat = (com.tecsys.gatewayplanner.rf.terrain.TerrainProvider) (a, b) -> 100;
        LinkResult sem = new TerrainDiffractionModel(flat).evaluate(LAT, lons[0], LAT, lons[1], p);
        LinkResult com = new TerrainDiffractionModel(flat, forest).evaluate(LAT, lons[0], LAT, lons[1], p);
        LinkResult perto = new TerrainDiffractionModel(flat, nearEnds).evaluate(LAT, lons[0], LAT, lons[1], p);
        assertTrue(com.pathLossDb() > sem.pathLossDb() + 3, "mata no caminho deve aumentar a perda: " + sem.pathLossDb() + " -> " + com.pathLossDb());
        assertEquals(sem.pathLossDb(), perto.pathLossDb(), 0.001);
    }
}
