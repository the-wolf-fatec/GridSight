package com.tecsys.gatewayplanner.planning;

import com.tecsys.gatewayplanner.rf.CoverageCalculator;
import com.tecsys.gatewayplanner.rf.CoverageMatrix;
import com.tecsys.gatewayplanner.rf.Geo;
import com.tecsys.gatewayplanner.rf.GeoSite;
import com.tecsys.gatewayplanner.rf.RadioParams;
import com.tecsys.gatewayplanner.rf.optimizer.OptimizerConstraints;
import com.tecsys.gatewayplanner.rf.optimizer.PlacementOptimizer;
import com.tecsys.gatewayplanner.rf.optimizer.SolutionDetail;
import com.tecsys.gatewayplanner.rf.propagation.FreeSpaceModel;
import com.tecsys.gatewayplanner.rf.propagation.LinkResult;
import com.tecsys.gatewayplanner.rf.propagation.PropagationModel;
import com.tecsys.gatewayplanner.rf.propagation.TerrainDiffractionModel;
import com.tecsys.gatewayplanner.rf.terrain.TerrainProvider;

import java.util.ArrayList;
import java.util.List;

/**
 * Planejamento de gateways considerando (ou não) o relevo. Não depende do
 * Spring: o {@code PlanningService} só passa o relevo e chama aqui.
 *
 * Como funciona, por distribuidora:
 *  1. Calcula, para cada par (local candidato, ativo) dentro do alcance, a perda
 *     de propagação — espaço livre + difração no relevo (SRTM .hgt).
 *     O enlace "fecha" se a perda cabe no orçamento: potência + 120 dBm (sensibilidade)
 *     - margem de 5 dB (árvores/prédios que o relevo não mostra).
 *  2. Escolhe os gateways pelo ganho conjunto (guloso + poda de redundantes + troca local).
 *  3. Cada ativo é atendido pelo gateway de melhor sinal.
 *  4. Para mostrar a INFLUÊNCIA do relevo, repete a escolha só por distância e
 *     compara: quantos gateways bastariam, e quantos ativos esses mesmos gateways
 *     perdem quando o relevo entra na conta.
 */
public final class PlanningEngine {

    /** Margem de desvanecimento padrão (dB). 0 = decide como o Longley-Rice (mediana); o app pode pedir mais. */
    public static final double DEFAULT_FADE_MARGIN_DB = 0;

    private static final int FOOTPRINT_BEARINGS = 36;
    private static final int FOOTPRINT_STEPS = 20;

    private PlanningEngine() {
    }

    /** Margem pedida pelo app (0..20 dB) ou, se não veio, a padrão do servidor. */
    private static double effectiveMargin(PlanRequest req, double serverDefault) {
        double m = req.fadeMarginDb != null ? req.fadeMarginDb : serverDefault;
        return Math.min(20, Math.max(0, m));
    }

    public static PlanResponse run(PlanRequest req, TerrainProvider terrain, double fadeMarginDb) {
        long t0 = System.nanoTime();
        if (!(req.rangeKm > 0)) throw new IllegalArgumentException("O alcance deve ser maior que zero.");

        RadioParams withTerrain = new RadioParams();
        withTerrain.txPowerDbm = req.txPowerDbm;
        withTerrain.fadeMarginDb = effectiveMargin(req, fadeMarginDb);
        withTerrain.maxRangeKm = Math.min(100, Math.max(0.05, req.rangeKm));
        withTerrain.gatewayHeightM = Math.min(100, Math.max(1, req.gatewayHeightM));
        withTerrain.useTerrain = true;
        withTerrain.validate();

        // "Só distância": mesmo teto de alcance, mas o orçamento de enlace nunca limita
        // (é o comportamento clássico do app: cobre quem está dentro do raio).
        RadioParams distanceOnly = withTerrain.copy();
        distanceOnly.useTerrain = false;
        distanceOnly.rxSensitivityDbm = -300;

        boolean useTerrain = req.useTerrain;
        boolean dataFound = !useTerrain || terrainDataPresent(req, terrain);
        List<String> warnings = new ArrayList<>();
        if (useTerrain && !dataFound) {
            warnings.add("Nenhum arquivo de relevo (.hgt) foi encontrado para esta região. O cálculo usou só a distância. "
                    + "Confira a pasta 'terrain' (GET /api/planning/terrain-status).");
            useTerrain = false;
        }

        List<String> chosenIds = new ArrayList<>();
        List<PlanResponse.Link> links = new ArrayList<>();
        List<String> lost = new ArrayList<>();
        List<PlanResponse.LostAsset> lostDetails = new ArrayList<>();
        List<PlanResponse.Footprint> footprints = new ArrayList<>();
        int total = 0, covered = 0, coveredByDistance = 0, overlapped = 0;
        int cmpGw = 0, cmpDist = 0, cmpTerr = 0;
        boolean anyComparison = false;
        long linksMissing = 0;

        for (PlanRequest.Group grp : req.groups) {
            if (grp.assets == null || grp.candidates == null || grp.assets.isEmpty()) continue;
            List<GeoSite> assets = toSites(grp.assets);
            List<GeoSite> cands = toSites(grp.candidates);
            total += assets.size();
            if (cands.isEmpty()) continue;

            boolean manual = grp.manualGatewayIds != null;
            OptimizerConstraints oc = new OptimizerConstraints();
            oc.maxGateways = Math.max(1, req.maxGateways);
            oc.minCoverageTarget = Math.min(1.0, Math.max(0.0, req.minCoverageTarget));

            CoverageMatrix flatM = CoverageCalculator.compute(cands, assets, distanceOnly, new FreeSpaceModel());
            CoverageMatrix mainM = flatM;
            RadioParams mainP = distanceOnly;
            PropagationModel model = new FreeSpaceModel();
            if (useTerrain) {
                model = new TerrainDiffractionModel(terrain);
                mainM = CoverageCalculator.compute(cands, assets, withTerrain, model);
                mainP = withTerrain;
                linksMissing += mainM.linksMissingTerrain();
            }

            SolutionDetail sol;
            if (manual) {
                List<Integer> idx = new ArrayList<>();
                for (String id : grp.manualGatewayIds) {
                    int i = mainM.indexOfCandidate(id);
                    if (i >= 0 && !idx.contains(i)) idx.add(i);
                }
                sol = SolutionDetail.of(mainM, idx, "Seleção manual");
            } else {
                sol = PlacementOptimizer.optimize(mainM, oc, 0).get(0);
                if (useTerrain) {
                    // O que o planejamento SEM relevo faria, e como esses gateways se saem COM relevo.
                    SolutionDetail flatSol = PlacementOptimizer.optimize(flatM, oc, 0).get(0);
                    SolutionDetail flatUnderTerrain = SolutionDetail.of(mainM, flatSol.gateways, "sem relevo, avaliado com relevo");
                    cmpGw += flatSol.gateways.size();
                    cmpDist += flatSol.covered;
                    cmpTerr += flatUnderTerrain.covered;
                    anyComparison = true;
                }
            }

            // Mesmo conjunto de gateways avaliado só por distância -> ativos perdidos por causa do relevo.
            SolutionDetail byDistance = SolutionDetail.of(flatM, sol.gateways, "distância");
            coveredByDistance += byDistance.covered;
            if (useTerrain) {
                // (1) ao alcance de um gateway escolhido, mas bloqueado pelo terreno;
                // (2) sem sinal de NENHUM candidato por causa do relevo, embora houvesse candidato dentro do raio.
                boolean[] anyByDistance = new boolean[assets.size()], anyWithTerrain = new boolean[assets.size()];
                for (int c = 0; c < cands.size(); c++) {
                    for (int a : flatM.coveredAssets(c)) anyByDistance[a] = true;
                    for (int a : mainM.coveredAssets(c)) anyWithTerrain[a] = true;
                }
                for (int a = 0; a < assets.size(); a++) {
                    if (sol.servingGateway[a] >= 0) continue;
                    boolean blockedForChosen = byDistance.servingGateway[a] >= 0;
                    boolean blockedForAll = anyByDistance[a] && !anyWithTerrain[a];
                    if (blockedForChosen || blockedForAll) {
                        lost.add(assets.get(a).id());
                        lostDetails.add(lostDetail(assets.get(a), cands, sol.gateways, withTerrain, terrain));
                    }
                }
            }

            covered += sol.covered;
            int[] reach = new int[assets.size()];
            for (int g : sol.gateways) {
                chosenIds.add(cands.get(g).id());
                for (int a : mainM.coveredAssets(g)) reach[a]++;
            }
            for (int r : reach) if (r >= 2) overlapped++;

            for (int a = 0; a < assets.size(); a++) {
                int g = sol.servingGateway[a];
                if (g < 0) continue;
                GeoSite gs = cands.get(g), as = assets.get(a);
                links.add(new PlanResponse.Link(as.id(), gs.id(), round(Geo.distanceKm(gs.lat(), gs.lon(), as.lat(), as.lon()), 3),
                        round(mainP.rxPowerDbm(sol.servingPathLossDb[a]), 1)));
            }

            if (useTerrain) {
                List<GeoSite> chosen = new ArrayList<>();
                for (int g : sol.gateways) chosen.add(cands.get(g));
                java.util.Map<Long, List<GeoSite>> grid = assetGrid(assets);
                for (int k = 0; k < chosen.size(); k++) {
                    PlanResponse.Footprint fp = footprint(chosen.get(k), mainP, model, terrain);
                    footprints.add(new PlanResponse.Footprint(fp.gatewayId(), fp.points(), fp.obstacles(),
                            shadows(chosen, k, mainP, model, grid)));
                }
            }
        }

        if (useTerrain && linksMissing > 0) {
            warnings.add(linksMissing + " enlace(s) caíram para distância por falta de dado de relevo (ladrilho .hgt ausente nessa área).");
        }

        PlanResponse.Comparison cmp = anyComparison ? new PlanResponse.Comparison(cmpGw, cmpDist, cmpTerr) : null;
        return new PlanResponse(useTerrain, dataFound, chosenIds, total, covered, links, lost, coveredByDistance,
                overlapped, cmp, footprints, warnings, (System.nanoTime() - t0) / 1_000_000, lostDetails);
    }

    /**
     * Área estimada de cobertura: em 36 direções, até onde o enlace ainda fecha
     * (parando no primeiro ponto que falha, ex.: atrás de um morro).
     */
    static PlanResponse.Footprint footprint(GeoSite g, RadioParams p, PropagationModel model, TerrainProvider terrain) {
        double budget = p.linkBudgetDb();
        List<double[]> pts = new ArrayList<>(FOOTPRINT_BEARINGS);
        List<PlanResponse.Obstacle> blockers = new ArrayList<>();
        for (int b = 0; b < FOOTPRINT_BEARINGS; b++) {
            double bearing = b * 360.0 / FOOTPRINT_BEARINGS;
            double step = p.maxRangeKm / FOOTPRINT_STEPS;
            double ok = 0;
            for (int i = 1; i <= FOOTPRINT_STEPS; i++) {
                double d = i * step;
                if (closes(g, bearing, d, p, model, budget)) {
                    ok = d;
                    continue;
                }
                double lo = ok, hi = d;
                for (int k = 0; k < 5; k++) {
                    double mid = (lo + hi) / 2;
                    if (closes(g, bearing, mid, p, model, budget)) lo = mid;
                    else hi = mid;
                }
                ok = lo;
                PlanResponse.Obstacle ob = obstacle(g, bearing, hi, p, terrain);
                if (ob != null) blockers.add(ob);
                break;
            }
            double[] ll = destination(g.lat(), g.lon(), bearing, ok);
            pts.add(new double[]{round(ll[0], 5), round(ll[1], 5)});
        }
        return new PlanResponse.Footprint(g.id(), pts, topObstacles(blockers), List.of());
    }

    /**
     * Pontos altos onde um gateway novo alcançaria ativos hoje sem sinal por causa do relevo.
     * Por grupo: roda o plano, pega os ativos perdidos, procura picos (máximos locais do terreno)
     * ao redor deles e escolhe, de forma gulosa, os que recuperam mais ativos.
     */
    public static List<PlanResponse.PeakSuggestion> suggestPeaks(PlanRequest req, TerrainProvider terrain, double fadeMarginDb) {
        List<PlanResponse.PeakSuggestion> out = new ArrayList<>();
        RadioParams p = new RadioParams();
        p.txPowerDbm = req.txPowerDbm;
        p.fadeMarginDb = effectiveMargin(req, fadeMarginDb);
        p.maxRangeKm = Math.min(100, Math.max(0.05, req.rangeKm));
        p.gatewayHeightM = Math.min(100, Math.max(1, req.gatewayHeightM));
        p.useTerrain = true;
        p.validate();
        PropagationModel model = new TerrainDiffractionModel(terrain);
        double budget = p.linkBudgetDb();
        int seq = 0;
        for (PlanRequest.Group grp : req.groups) {
            if (grp.assets == null || grp.assets.isEmpty()) continue;
            PlanRequest one = new PlanRequest();
            one.rangeKm = req.rangeKm; one.txPowerDbm = req.txPowerDbm; one.minCoverageTarget = req.minCoverageTarget;
            one.maxGateways = req.maxGateways; one.gatewayHeightM = req.gatewayHeightM; one.useTerrain = true;
            one.groups = List.of(grp);
            PlanResponse r = run(one, terrain, fadeMarginDb);
            if (!r.terrainUsed() || r.lostToTerrainAssetIds().isEmpty()) continue;
            java.util.Set<String> lostIds = new java.util.HashSet<>(r.lostToTerrainAssetIds());
            List<GeoSite> lost = new ArrayList<>();
            for (GeoSite a : toSites(grp.assets)) if (lostIds.contains(a.id())) lost.add(a);
            if (lost.size() > 600) lost = new ArrayList<>(lost.subList(0, 600));

            // grade de busca ao redor dos ativos perdidos (raio de busca <= 6 km, passo ~450 m)
            double reach = Math.min(p.maxRangeKm, 6.0);
            double step = 0.004;
            double dLat = reach / 111.195;
            double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
            for (GeoSite a : lost) {
                minLat = Math.min(minLat, a.lat()); maxLat = Math.max(maxLat, a.lat());
                minLon = Math.min(minLon, a.lon()); maxLon = Math.max(maxLon, a.lon());
            }
            double dLon = dLat / Math.max(0.2, Math.cos(Math.toRadians((minLat + maxLat) / 2)));
            int ny = (int) Math.ceil((maxLat - minLat + 2 * dLat) / step) + 1, nx = (int) Math.ceil((maxLon - minLon + 2 * dLon) / step) + 1;
            if ((long) ny * nx > 40000) continue; // área grande demais: não sugere (evita travar)
            double lat0 = minLat - dLat, lon0 = minLon - dLon;
            double[][] z = new double[ny][nx];
            for (int i = 0; i < ny; i++) for (int j = 0; j < nx; j++) z[i][j] = terrain.elevationM(lat0 + i * step, lon0 + j * step);
            List<double[]> peaks = new ArrayList<>(); // lat, lon, elevação
            for (int i = 1; i < ny - 1; i++) {
                for (int j = 1; j < nx - 1; j++) {
                    double v = z[i][j];
                    if (Double.isNaN(v)) continue;
                    boolean peak = true;
                    for (int di = -1; di <= 1 && peak; di++) for (int dj = -1; dj <= 1; dj++) {
                        if ((di != 0 || dj != 0) && !(z[i + di][j + dj] <= v)) { peak = false; break; }
                    }
                    if (!peak) continue;
                    double la = lat0 + i * step, lo = lon0 + j * step;
                    boolean near = false;
                    for (GeoSite a : lost) if (Geo.distanceKm(la, lo, a.lat(), a.lon()) <= reach) { near = true; break; }
                    if (near) peaks.add(new double[]{la, lo, v});
                }
            }
            if (peaks.size() > 400) { // fica com os 400 mais altos
                peaks.sort((x, y) -> Double.compare(y[2], x[2]));
                peaks = new ArrayList<>(peaks.subList(0, 400));
            }
            // quais ativos perdidos cada pico alcança
            List<java.util.BitSet> reachSets = new ArrayList<>();
            for (double[] pk : peaks) {
                GeoSite site = new GeoSite("pk", "pk", "", pk[0], pk[1]);
                java.util.BitSet bs = new java.util.BitSet(lost.size());
                for (int k = 0; k < lost.size(); k++) {
                    GeoSite a = lost.get(k);
                    if (Geo.distanceKm(pk[0], pk[1], a.lat(), a.lon()) > p.maxRangeKm) continue;
                    if (closesPoint(site, a.lat(), a.lon(), p, model, budget)) bs.set(k);
                }
                reachSets.add(bs);
            }
            // escolha gulosa: até 5 picos, cada um com pelo menos 2 ativos novos
            java.util.BitSet done = new java.util.BitSet(lost.size());
            for (int pick = 0; pick < 5; pick++) {
                int bestI = -1, bestGain = 1;
                for (int i = 0; i < peaks.size(); i++) {
                    java.util.BitSet t = (java.util.BitSet) reachSets.get(i).clone();
                    t.andNot(done);
                    int gain = t.cardinality();
                    if (gain > bestGain) { bestGain = gain; bestI = i; }
                }
                if (bestI < 0) break;
                done.or(reachSets.get(bestI));
                double[] pk = peaks.get(bestI);
                out.add(new PlanResponse.PeakSuggestion("pico-" + (++seq), grp.name, round(pk[0], 5), round(pk[1], 5), Math.round(pk[2]), bestGain));
            }
        }
        return out;
    }

    /** Altitude do ativo perdido e o morro que o isola do gateway mais próximo (escolhido, ou candidato se não houver). */
    private static PlanResponse.LostAsset lostDetail(GeoSite a, List<GeoSite> cands, List<Integer> chosen, RadioParams p, TerrainProvider terrain) {
        GeoSite ref = null;
        double best = Double.MAX_VALUE;
        for (int g : chosen) {
            double d = Geo.distanceKm(cands.get(g).lat(), cands.get(g).lon(), a.lat(), a.lon());
            if (d <= p.maxRangeKm && d < best) { best = d; ref = cands.get(g); }
        }
        if (ref == null) {
            for (GeoSite c : cands) {
                double d = Geo.distanceKm(c.lat(), c.lon(), a.lat(), a.lon());
                if (d <= p.maxRangeKm && d < best) { best = d; ref = c; }
            }
        }
        double z = terrain.elevationM(a.lat(), a.lon());
        PlanResponse.Obstacle ob = null;
        if (ref != null && best > 0.01) {
            ob = obstacle(ref, bearing(ref.lat(), ref.lon(), a.lat(), a.lon()), best, p, terrain);
        }
        return new PlanResponse.LostAsset(a.id(), Double.isNaN(z) ? -9999 : Math.round(z), ref == null ? null : ref.id(), ob);
    }

    private static double bearing(double lat1, double lon1, double lat2, double lon2) {
        double p1 = Math.toRadians(lat1), p2 = Math.toRadians(lat2), dl = Math.toRadians(lon2 - lon1);
        double y = Math.sin(dl) * Math.cos(p2);
        double x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
        return (Math.toDegrees(Math.atan2(y, x)) + 360) % 360;
    }

    /** Só desenha área sem sinal até esta distância do gateway (o modelo só foi validado até ~10 km). */
    private static final double SHADOW_MAX_KM = 15;
    /** Só vale como "sem sinal" onde há rede de distribuição: a até esta distância de algum ativo (a área sem sinal é desenhada em manchas grandes em volta da rede). */
    private static final double SHADOW_NEAR_ASSET_KM = 6.0;
    private static final double GRID_DEG = 0.02;

    private static long gridKey(double lat, double lon) {
        return (((long) Math.floor(lat / GRID_DEG)) << 32) ^ (((long) Math.floor(lon / GRID_DEG)) & 0xFFFFFFFFL);
    }

    static java.util.Map<Long, List<GeoSite>> assetGrid(List<GeoSite> assets) {
        java.util.Map<Long, List<GeoSite>> m = new java.util.HashMap<>();
        for (GeoSite a : assets) m.computeIfAbsent(gridKey(a.lat(), a.lon()), x -> new ArrayList<>()).add(a);
        return m;
    }

    private static boolean nearAsset(java.util.Map<Long, List<GeoSite>> grid, double lat, double lon) {
        for (int di = -1; di <= 1; di++) {
            for (int dj = -1; dj <= 1; dj++) {
                List<GeoSite> l = grid.get(gridKey(lat + di * GRID_DEG, lon + dj * GRID_DEG));
                if (l == null) continue;
                for (GeoSite a : l) if (Geo.distanceKm(lat, lon, a.lat(), a.lon()) <= SHADOW_NEAR_ASSET_KM) return true;
            }
        }
        return false;
    }

    private static final int SHADOW_SECTORS = 90;
    private static final int SHADOW_RINGS = 24;

    /**
     * "Buracos" no alcance do gateway {@code k}: células do círculo (setores de 5° x anéis) onde o sinal
     * não chega por causa do relevo E que nenhum outro gateway escolhido atende. Pode haver buracos no meio
     * do alcance (atrás de uma serra, com sinal de volta mais adiante). Células vizinhas na mesma direção
     * são unidas num só quadrilátero. Uma célula alcançada por vários gateways é devolvida só pelo primeiro.
     */
    static List<List<double[]>> shadows(List<GeoSite> chosen, int k, RadioParams p, PropagationModel model,
                                        java.util.Map<Long, List<GeoSite>> grid) {
        GeoSite g = chosen.get(k);
        double budget = p.linkBudgetDb();
        double reach = Math.min(p.maxRangeKm, SHADOW_MAX_KM);
        double ring = reach / SHADOW_RINGS;
        double halfSector = 360.0 / SHADOW_SECTORS / 2 * 1.08; // 8% de sobreposição: sem frestas entre setores vizinhos
        List<List<double[]>> out = new ArrayList<>();
        for (int s = 0; s < SHADOW_SECTORS; s++) {
            double bearing = s * 360.0 / SHADOW_SECTORS;
            int runStart = -1;
            for (int i = 0; i <= SHADOW_RINGS; i++) {
                boolean hole = false;
                if (i < SHADOW_RINGS) {
                    double mid = (i + 0.5) * ring;
                    double[] c = destination(g.lat(), g.lon(), bearing, mid);
                    hole = nearAsset(grid, c[0], c[1]) && !closesPoint(g, c[0], c[1], p, model, budget) && !servedByOther(chosen, k, c, p, model, budget);
                }
                if (hole && runStart < 0) runStart = i;
                if (!hole && runStart >= 0) {
                    double r0 = runStart * ring, r1 = i * ring;
                    double[] a = destination(g.lat(), g.lon(), bearing - halfSector, r0);
                    double[] b = destination(g.lat(), g.lon(), bearing + halfSector, r0);
                    double[] c2 = destination(g.lat(), g.lon(), bearing + halfSector, r1);
                    double[] d = destination(g.lat(), g.lon(), bearing - halfSector, r1);
                    out.add(List.of(new double[]{round(a[0], 5), round(a[1], 5)}, new double[]{round(b[0], 5), round(b[1], 5)},
                            new double[]{round(c2[0], 5), round(c2[1], 5)}, new double[]{round(d[0], 5), round(d[1], 5)}));
                    runStart = -1;
                }
            }
        }
        return out;
    }

    /** O ponto é atendido por outro gateway escolhido, ou já pertence à área de um gateway de índice menor. */
    private static boolean servedByOther(List<GeoSite> chosen, int k, double[] pt, RadioParams p, PropagationModel model, double budget) {
        for (int h = 0; h < chosen.size(); h++) {
            if (h == k) continue;
            GeoSite o = chosen.get(h);
            if (Geo.distanceKm(o.lat(), o.lon(), pt[0], pt[1]) > p.maxRangeKm) continue;
            if (h < k) return true; // o gateway de índice menor é quem desenha esta célula
            if (closesPoint(o, pt[0], pt[1], p, model, budget)) return true;
        }
        return false;
    }

    private static boolean closesPoint(GeoSite g, double lat, double lon, RadioParams p, PropagationModel model, double budget) {
        LinkResult r = model.evaluate(g.lat(), g.lon(), lat, lon, p);
        return r.pathLossDb() <= budget;
    }

    /**
     * Ponto do relevo que mais passa acima da linha de visada entre o gateway e o ponto onde o
     * sinal deixou de chegar ({@code failKm}). Devolve null se nada passa (falha por distância).
     */
    private static PlanResponse.Obstacle obstacle(GeoSite g, double bearing, double failKm, RadioParams p, TerrainProvider terrain) {
        double[] end = destination(g.lat(), g.lon(), bearing, failKm);
        double gz = terrain.elevationM(g.lat(), g.lon());
        double ez = terrain.elevationM(end[0], end[1]);
        if (Double.isNaN(gz) || Double.isNaN(ez)) return null;
        double top0 = gz + p.gatewayHeightM, top1 = ez + p.deviceHeightM;
        final int n = 40;
        double best = 0;
        PlanResponse.Obstacle res = null;
        for (int i = 1; i < n; i++) {
            double f = (double) i / n;
            double d = failKm * f;
            double[] ll = destination(g.lat(), g.lon(), bearing, d);
            double z = terrain.elevationM(ll[0], ll[1]);
            if (Double.isNaN(z)) continue;
            // curvatura da Terra (k = 4/3): o horizonte "sobe" no meio do caminho
            double bulge = d * (failKm - d) * 1000.0 / (2 * 1.3333 * Geo.EARTH_RADIUS_KM);
            double above = z + bulge - (top0 + (top1 - top0) * f);
            if (above > best) {
                best = above;
                res = new PlanResponse.Obstacle(round(ll[0], 5), round(ll[1], 5), Math.round(z), Math.round(above), round(d, 2));
            }
        }
        return res != null && best >= 5 ? res : null;
    }

    /** Os obstáculos mais altos, sem repetir o mesmo morro (pontos a menos de 2 km são o mesmo). */
    private static List<PlanResponse.Obstacle> topObstacles(List<PlanResponse.Obstacle> all) {
        List<PlanResponse.Obstacle> sorted = new ArrayList<>(all);
        sorted.sort((a, b) -> Double.compare(b.elevationM(), a.elevationM()));
        List<PlanResponse.Obstacle> out = new ArrayList<>();
        for (PlanResponse.Obstacle o : sorted) {
            boolean dup = false;
            for (PlanResponse.Obstacle k : out) {
                if (Geo.distanceKm(o.lat(), o.lon(), k.lat(), k.lon()) < 2.0) {
                    dup = true;
                    break;
                }
            }
            if (!dup) out.add(o);
            if (out.size() >= 6) break;
        }
        return out;
    }

    private static boolean closes(GeoSite g, double bearing, double distKm, RadioParams p, PropagationModel model, double budget) {
        double[] ll = destination(g.lat(), g.lon(), bearing, distKm);
        LinkResult r = model.evaluate(g.lat(), g.lon(), ll[0], ll[1], p);
        return r.pathLossDb() <= budget;
    }

    /** Ponto a {@code distKm} do ponto de origem, na direção {@code bearingDeg} (0 = norte). */
    static double[] destination(double lat, double lon, double bearingDeg, double distKm) {
        double d = distKm / Geo.EARTH_RADIUS_KM, th = Math.toRadians(bearingDeg);
        double p1 = Math.toRadians(lat), l1 = Math.toRadians(lon);
        double p2 = Math.asin(Math.sin(p1) * Math.cos(d) + Math.cos(p1) * Math.sin(d) * Math.cos(th));
        double l2 = l1 + Math.atan2(Math.sin(th) * Math.sin(d) * Math.cos(p1), Math.cos(d) - Math.sin(p1) * Math.sin(p2));
        return new double[]{Math.toDegrees(p2), Math.toDegrees(l2)};
    }

    /** Amostra alguns pontos e vê se o relevo responde (arquivo .hgt presente). */
    private static boolean terrainDataPresent(PlanRequest req, TerrainProvider terrain) {
        int tried = 0, ok = 0;
        for (PlanRequest.Group g : req.groups) {
            List<PlanRequest.Site> all = new ArrayList<>();
            if (g.candidates != null) all.addAll(g.candidates);
            if (g.assets != null) all.addAll(g.assets);
            int stride = Math.max(1, all.size() / 40);
            for (int i = 0; i < all.size(); i += stride) {
                tried++;
                if (!Double.isNaN(terrain.elevationM(all.get(i).lat, all.get(i).lon))) ok++;
            }
        }
        return tried > 0 && ok * 2 >= tried;
    }

    private static List<GeoSite> toSites(List<PlanRequest.Site> in) {
        List<GeoSite> out = new ArrayList<>(in.size());
        for (PlanRequest.Site s : in) {
            out.add(new GeoSite(s.id, s.name == null ? s.id : s.name, s.type == null ? "" : s.type, s.lat, s.lon));
        }
        return out;
    }

    private static double round(double v, int decimals) {
        double f = Math.pow(10, decimals);
        return Math.round(v * f) / f;
    }

}
